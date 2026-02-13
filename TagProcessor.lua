local log = LogManager.GetLogger(rootLogger .. ".TagProcessor");

local TagProcessorInternal = {};

TagProcessor = TagProcessorInternal;

TagProcessorInternal.CustomReplacements = {};
TagProcessorInternal.NullValueReplacement = "";

local function AddCustom(name, handler)
	TagProcessorInternal.CustomReplacements[name] = handler;
end


local function MapCustomFieldValue(fieldDefinition)
	if (fieldDefinition) then
		log:Debug("[TagProcessor] Mapping Custom FieldValue for " .. fieldDefinition);
		
		--Looks for functional calls to account for more than just simple tag replacement
		--If the custom handler should only be a fieldvalue, use "return value" as the function
		if (TagProcessorInternal.CustomReplacements[fieldDefinition] ~= nil and TagProcessorInternal.CustomReplacements[fieldDefinition] ~= "") then
			log:DebugFormat("Found {0} tag replacement handler", fieldDefinition);
			local successfulCustomReplacement, customReplacement = pcall(TagProcessorInternal.CustomReplacements[fieldDefinition]);
			if (not successfulCustomReplacement) then
				log:WarnFormat("Custom replacement not found for {0}", fieldDefinition);
			else
				log:DebugFormat("Custom replacement found for {0}: {1}", fieldDefinition, customReplacement);
				value = customReplacement;					
			end
		end

		log:DebugFormat("Custom replacement value: {0}", value);
		if ((value == nil) or (value == DBNull.Value)) then
			log:Debug("Replacement value is null.");				
			value = TagProcessorInternal.NullValueReplacement;
		end

		return value;
	end

	return "";
end

local function MapFieldValue(fieldDefinition)
	if (fieldDefinition) then
		log:Debug("[TagProcessor] Mapping FieldValue for " .. fieldDefinition);
		local separatorIndex = string.find(fieldDefinition, "%.");

		-- To support Aeon custom fields (format: [Table].CustomFields.[FieldName]), get the index of the second "."
		-- since [Table].CustomFields is used as the table with GetFieldValue.
		local customFieldSeparatorIndex = select(2, string.find(fieldDefinition:lower(), "%.customfields%."));

		if (separatorIndex and separatorIndex > 0) then
			local table = nil;
			local field = nil;

			if (customFieldSeparatorIndex) then
				table = string.sub(fieldDefinition, 1, customFieldSeparatorIndex - 1);
				field = string.sub(fieldDefinition, customFieldSeparatorIndex + 1);
			else
				table = string.sub(fieldDefinition, 1, separatorIndex - 1);
				field = string.sub(fieldDefinition, separatorIndex + 1);
			end

			local value = nil;

			if (table == "Setting") then
				log:Debug("[TagProcessor] Getting TableField. Setting: " .. field);
				value = GetSetting(field);
			elseif (table == "Custom") then
				log:Debug("[TagProcessor] Getting TableField. Custom: " .. field);
				if (TagProcessorInternal.CustomReplacements[table] ~= "") then
					log:DebugFormat("Found {0} tag replacement handler", table);
					local successfulCustomReplacement, customReplacement = pcall(TagProcessorInternal.CustomReplacements[table], field);
					if successfulCustomReplacement then
						value = customReplacement;
					end
				end
			elseif (table == "LocalInfo") then
				--LocalInfo is not a field available from GetFieldValue so we have to override it and look for a custom replacement
				log:DebugFormat("[TagProcessor] Getting LocalInfo Field: {0}", field);
				value = MapCustomFieldValue(fieldDefinition);
			else
				log:Debug("[TagProcessor] Getting TableField. Table: ".. table .. ". Field: " .. field .. ".");
				value = GetFieldValue(table, field);
			end

			if ((value == nil) or (value == DBNull.Value)) then
				log:Debug("[TagProcessor] Replacement value is null.");
				value = "";
			end

			return value;
		end

		return value;
		
	end

	return "";
end

local function ReplaceTag(input)
    log:Debug('Process tag replacements for '..input);

    if (input == nil) then
        return '';
	end
	
	local tag = input;

    local escapeQuotes = false;

    local escapeQuotesIndex = string.find(tag, ",EscapeQuotes");

    if (escapeQuotesIndex and escapeQuotesIndex > 0) then
      --Remove the ",EscapeQuotes"
      tag = string.sub(tag, 1, escapeQuotesIndex - 1);
      escapeQuotes = true;
      log:DebugFormat("Tag will be escaped: {0}", tag);
    else
      log:DebugFormat("Tag will not be escaped: {0}", tag);
    end

    if (tag:sub(1,11):lower() == "tablefield:") then
		returnValue = MapFieldValue(tag:sub(12));
	elseif (tag:sub(1,7):lower() == "custom:") then		
		log:DebugFormat("[TagProcessor] Getting Custom Field: {0}", field);
		returnValue = MapCustomFieldValue(tag:sub(8));     		
	elseif (tag:sub(1,5):lower() == "date:") then
		local formatting = tag:sub(6);
		log:Debug("[TagProcessor] Getting TableField. Date: " .. formatting);		
		datetime = DateTime.Now;
		returnValue = datetime:ToString(formatting);
    else
        return '';
	end
	
	if (escapeQuotes) then
		returnValue = tostring(returnValue):gsub('"', '\"');
	end
	return returnValue;

end

local function ReplaceTags(input, pattern)
	log:DebugFormat("input: {0}", input);
	return input:gsub( (pattern or '{(.-)}'), function( token ) return ReplaceTag(token) end );
end

local function ReplaceLuaTable(obj, seen)
  -- Handle non-tables and previously-seen tables.
	if type(obj) ~= 'table' then
		if (obj and type(obj) == "string") then
			return ReplaceTags(obj);
		end
		return obj;
	end
  if seen and seen[obj] then return seen[obj] end

  -- New table; mark it as seen an copy recursively.
  local s = seen or {}
  local res = setmetatable({}, getmetatable(obj))
  s[obj] = res
  for k, v in pairs(obj) do res[ReplaceLuaTable(k, s)] = ReplaceLuaTable(v, s) end
  return res
end

-- Exports
TagProcessor.ReplaceTags = ReplaceTags;
TagProcessor.AddCustom = AddCustom;
TagProcessor.ReplaceLuaTable = ReplaceLuaTable;
