-- Aeon ArchivesSpace Import
-- This addon will utilize the ArchivesSpace API to look up the collection/item information matching a request in Aeon.
-- Please see README for workflow and configuration explanation.

luanet.load_assembly("System");
luanet.load_assembly("System.Xml");
luanet.load_assembly("log4net");
require("JsonParser");
require("AtlasHelpers");

local Types = {};
Types["System.Net.WebClient"] = luanet.import_type("System.Net.WebClient");
Types["System.Text.Encoding"] = luanet.import_type("System.Text.Encoding");
Types["System.Xml.XmlDocument"] = luanet.import_type("System.Xml.XmlDocument");
Types["log4net.LogManager"] = luanet.import_type("log4net.LogManager");

local Settings = {};
Settings.RequestMonitorQueue = GetSetting("RequestMonitorQueue");
Settings.SuccessRouteQueue = GetSetting("SuccessRouteQueue");
Settings.ErrorRouteQueue = GetSetting("ErrorRouteQueue");
Settings.ApiBaseURL = GetSetting("ArchivesSpaceApiUrl");
Settings.ArchivesSpaceUsername = GetSetting("ArchivesSpaceUsername");
Settings.ArchivesSpacePassword = GetSetting("ArchivesSpacePassword");
Settings.TopContainerUriField = GetSetting("TopContainerUriField");
Settings.RepoCodeField = GetSetting("RepoCodeField");
Settings.RepoIdMapping = AtlasHelpers.StringSplit(",", GetSetting("RepoIdMapping"));
Settings.BarcodeField = GetSetting("BarcodeField");
Settings.LocationDestinationField = GetSetting("LocationDestinationField");

local addonName = "AeonASpaceImport";
local addonVersion = GetAddonVersion();
local rootLogger = "AtlasSystems.Addons." .. addonName;
local log = Types["log4net.LogManager"].GetLogger(rootLogger);
local sessionId;
local sessionTimeStamp;

function Init()
    RegisterSystemEventHandler("SystemTimerElapsed","InitiateASpaceImport");
end

function InitiateASpaceImport()
    log:Debug("Initiate ArchivesSpace Import");

    ProcessDataContexts("transactionstatus", Settings.RequestMonitorQueue, "ImportASpaceInfo");
end

function ImportASpaceInfo()
    sessionId = GetSessionId();
    local transactionNumber = GetFieldValue("Transaction", "TransactionNumber");

    if (sessionId == nil or sessionId == "") then
        log:Info("Unable to retrieve auth session token from ArchiveSpace API. Skipping this processing interval. The addon will try again on the next interval.")
        return;
    end

    local barcode = TagProcessor.ReplaceTags(Settings.BarcodeField);

    if Settings.TopContainerUriField ~= "" then
        if GetFieldValue("Transaction.CustomFields", Settings.TopContainerUriField) == "" then
            log:Info("Top container URI is missing from " .. Settings.TopContainerUriField .. " for Transaction " .. transactionNumber);
            return;
        end

        local topContainerUri = GetFieldValue("Transaction.CustomFields", Settings.TopContainerUriField) .. "?resolve%5B%5D=container_locations";
        
        local success, location = pcall(ImportByTopContainerUri, topContainerUri);
        if success and NotNilOrBlank(location) then
            SetLocationAndRoute(location, transactionNumber);
        else
            HandleLocationError(location, transactionNumber, barcode);
        end

    elseif Settings.RepoCodeField ~= "" then
        local repoCode = TagProcessor.ReplaceTags(Settings.RepoCodeField);
        
        if repoCode == "" then
            log:Info("repo_code is missing from " .. Settings.RepoCodeField:match("%.(.+)}") .. " for Transaction " .. transactionNumber);
            return;
        end

        local success, repoId = pcall(GetRepoId, repoCode);
        if success and NotNilOrBlank(repoId) then
            local success, location = pcall(ImportByRepoIdAndBarcode, repoId, barcode);
            if success and NotNilOrBlank(location) then
                SetLocationAndRoute(location, transactionNumber);
            else
                HandleLocationError(location, transactionNumber, barcode);
            end

        else
            if not NotNilOrBlank(repoId) then
                log:Info("Repo ID not found for Transaction " .. transactionNumber .. " with repo_code " .. repoCode);
            else
                OnError(repoId);
            end
            
            ExecuteCommand("Route", {transactionNumber, Settings.ErrorRouteQueue});
        end

    elseif #Settings.RepoIdMapping > 0 then
        local siteCode = GetFieldValue("Transaction", "Site");
        local repoId = nil;
        for i = 1, #Settings.RepoIdMapping do
            if Settings.RepoIdMapping[i]:lower():find(siteCode:lower()) then
                repoId = Settings.RepoIdMapping[i]:match("^(%d+)=");
                break;
            end
        end

        if not repoId then
            log:Info("Unable to determine repo ID from RepoIdMapping.");
            return;
        end
        
        local success, location = pcall(ImportByRepoIdAndBarcode, repoId, barcode);
        if success and NotNilOrBlank(location) then
            SetLocationAndRoute(location, transactionNumber);
        else
            HandleLocationError(location, transactionNumber, barcode);
        end
    else
        log:Info("Invalid configuration. TopContainerUri, RepoCodeField, or RepoIdMapping must contain a value.");
        return;
    end

end

function ImportByTopContainerUri(topContainerUri)
    log:Debug("Retrieving ASpace info for top level container " .. topContainerUri);
    local response = SendApiRequest(topContainerUri, "GET", nil, sessionId);
    log:Debug("API request completed");

    local parsedResponse = JsonParser:ParseJSON(response);
    local location = GetCurrentContainerLocation(parsedResponse);
    if location ~= nil then
        log:Debug("Location: " .. location);
    else
        log:Debug("No location found for container " .. topContainerUri);
    end

    return location;
end

function ImportByRepoIdAndBarcode(repoId, barcode)
    log:Debug("Retrieving ASpace info for barcode " .. barcode);

    local apiPath = "/repositories/" .. repoId .. "/top_containers/search?q=" .. barcode .. "&fields[]=json&page=1";
    local response = SendApiRequest(apiPath, "GET", nil, sessionId);
    log:Debug("API Request completed");
    
    local parsedResponse = JsonParser:ParseJSON(response);

    local location = GetCurrentContainerLocation(parsedResponse);
    if NotNilOrBlank(location) then
        log:Debug("Location: " .. location);
    else
        log:Debug("No location found for barcode " .. barcode .. " in repo " .. repoId);
    end

    return location;
end

function GetRepoId(repoCode)
    log:Debug("Retrieving list of ASpace repos");

    local apiPath = "/repositories";
    local response = SendApiRequest(apiPath, "GET", nil, sessionId);
    log:Debug("API Request completed");

    local parsedResponse = JsonParser:ParseJSON(response);

    local repoId = nil;
    for i = 1, #parsedResponse do
        if parsedResponse[i].repo_code == repoCode then
            repoId = parsedResponse[i].uri:match("%d+$");
            break;
        end
    end

    if NotNilOrBlank(repoId) then
        log:Debug("Repo ID: " .. repoId);
    else
        log:Debug("No repo ID found for repo_code " .. repoCode);
    end

    return repoId;
end

function GetCurrentContainerLocation(parsedResponse)
    -- The response from the /repositories/[repoId]/top_containers endpoint has the JSON we need in a "json" field
    log:Debug("Response first JSON field: " .. tostring(parsedResponse["response"]["docs"][1]["json"]));

    local containerLocations = parsedResponse.container_locations or JsonParser:ParseJSON(parsedResponse["response"]["docs"][1]["json"]).container_locations;
    local currentContainerLocationTitle;
    for i = 1, #containerLocations do
        if containerLocations[i].status == "current" then
            currentContainerLocationTitle = containerLocations[i]._resolved.title;
            break;
        end
    end

    return currentContainerLocationTitle;
end

function SetLocationAndRoute(location, transactionNumber)
    SetFieldValue("Transaction" , Settings.LocationDestinationField, location);
    SaveDataSource("Transaction");
    ExecuteCommand("Route", {transactionNumber, Settings.SuccessRouteQueue});
end

function GetAuthenticationToken()
    local authenticationToken = JsonParser:ParseJSON(SendApiRequest('/users/' .. Settings.ArchivesSpaceUsername .. '/login', 'POST', "password=" .. Settings.ArchivesSpacePassword));

    if (authenticationToken == nil or authenticationToken == JsonParser.NIL) then
        log:Error("Unable to get valid authentication token.");
        return;
    end

    return authenticationToken;
end

function GetSessionId()
    if (sessionId == nil or sessionId == "" or (sessionTimeStamp + 60 * 60) < os.time()) then
        log:Debug("Renewing ArchivesSpace authentication token.");
        local authentication = GetAuthenticationToken();

        sessionId = ExtractProperty(authentication, "session");

        if (sessionId == nil or sessionId == JsonParser.NIL) then
            log:Error("Unable to get valid session ID token.");
            return;
        end

        sessionTimeStamp = os.time();
    end

    return sessionId;
end

function SendApiRequest(apiPath, method, parameters, sessionId)
    local webClient = Types["System.Net.WebClient"]();

    webClient.Headers:Clear();
    webClient.Headers:Add("User-Agent", addonName .. "/" .. addonVersion);
    if (sessionId ~= nil and sessionId ~= "") then
        webClient.Headers:Add("X-ArchivesSpace-Session", sessionId);
    end

    local success, result;

    if (method == 'POST') then
        success, result = pcall(WebClientPost, webClient, apiPath, method, parameters);
    else
        success, result = pcall(WebClientGet, webClient, apiPath);
    end

    webClient:Dispose();

    if (success) then
        log:Debug("API call successful");
        log:Debug("Response: " .. result);
        return result;
    else
        log:Debug("API call error");
        OnError(result);
        return "";
    end
end

function HandleLocationError(location, transactionNumber, barcode);
    if not NotNilOrBlank(location) then
        log:Info("No location found for Transaction " .. transactionNumber .. " with barcode " .. barcode);
    else
        OnError(location);
    end

    ExecuteCommand("Route", {transactionNumber, Settings.ErrorRouteQueue});
end

function ObjectToString(o)
    if type(o) == 'table' then
       local s = '{ '
       for k,v in pairs(o) do
          if type(k) ~= 'number' then k = '"'..k..'"' end
          s = s .. '['..k..'] = ' .. ObjectToString(v) .. ','
       end
       return s .. '} '
    else
       return tostring(o)
    end
 end

function ExtractProperty(object, property)
    if object then
        return EmptyStringIfNil(object[property]);
    end
end

function EmptyStringIfNil(value)
    if (value == nil or value == JsonParser.NIL) then
        return "";
    else
        return value;
    end
end

function WebClientPost(webClient, apiPath, method, postParameters)
    return webClient:UploadString(PathCombine(Settings.ApiBaseURL, apiPath), method, postParameters);
end

function WebClientGet(webClient, apiPath)
    return webClient:DownloadString(PathCombine(Settings.ApiBaseURL, apiPath));
end

function OnError(e)
    if e == nil then
        log:Error("OnError supplied a nil error");
        return;
    end

    if not e.GetType then
        -- Not a .NET type
        -- Attempt to log value
        pcall(function ()
            log:Error(e);
        end);
        return;
    else
        if not e.Message then
            log:Error(e:ToString());
            return;
        end
    end

    local message = TraverseError(e);

    if message == nil then
        message = "Unspecified Error";
    end

    log:Error("An error occurred while processing the ArchivesSpace API request:\r\n" .. message);
end

function TraverseError(e)
    if not e.GetType then
        -- Not a .NET type
        return nil;
    else
        if not e.Message then
            -- Not a .NET exception
            log:Debug(e:ToString());
            return nil;
        end
    end

    log:Debug(e.Message);

    if e.InnerException then
        return TraverseError(e.InnerException);
    else
        return e.Message;
    end
end

function GetAddonVersion()
    local success, result = pcall(function()
        local configDoc = Types["System.Xml.XmlDocument"]();
        configDoc:Load("config.xml");
        local versionNode = configDoc:SelectSingleNode("/Configuration/Version");
        if versionNode then
            return versionNode.InnerText;
        end
    end);

    if success and result then
        return result;
    end
    return "0.0.0";
end

function PathCombine(path1, path2)
    local trailingSlashPattern = '/$';
    local leadingSlashPattern = '^/';

    if (path1 and path2) then
        local result = path1:gsub(trailingSlashPattern, '') .. '/' .. path2:gsub(leadingSlashPattern, '');
        return result;
    else
        return "";
    end
end

function NotNilOrBlank(value)
    if value == nil or value == JsonParser.NIL or value == "" then
        return false;
    else
        return true;
    end
end