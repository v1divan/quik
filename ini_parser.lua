-- ini_parser.lua
-- Simple INI file parser for Lua
-- Debugging version with detailed output.

local function trim(s)
    if type(s) ~= "string" then return s end
    return s:gsub("^%s+", ""):gsub("%s+$", "")
end

-- Parses a comma-separated string into a list (table).
-- Includes extensive debugging output.
local function parseList(listStr)
    print("DEBUG: parseList called with input: '" .. tostring(listStr) .. "'")
    local container = {}
    print("DEBUG: Initial container type: " .. type(container) .. ", value: " .. tostring(container))

    if not listStr or listStr == "" then
        print("DEBUG: Input was empty or nil, returning empty container.")
        return container
    end

    print("DEBUG: Starting gmatch loop on input: '" .. listStr .. "'")
    local item_count = 0
    for item in string.gmatch(listStr, "[^,]+") do
        item_count = item_count + 1
        print("DEBUG: Iteration " .. item_count .. ", item from gmatch: '" .. tostring(item) .. "'")
        print("DEBUG: Container type just before insert: " .. type(container) .. ", value: " .. tostring(container))

        -- Check type immediately before insert
        if type(container) ~= "table" then
             print("INI Parser CRITICAL ERROR: Target for insertion is not a table!")
             print("  - Input string was: '" .. tostring(listStr) .. "'")
             print("  - Item to insert was: '" .. tostring(item) .. "'")
             print("  - Container type is: " .. type(container))
             print("  - Container value is: " .. tostring(container))
             print("  - Iteration number: " .. item_count)
             -- Return a safe table or error, depending on desired behavior
             return {}
        end

        local trimmed_item = trim(item)
        print("DEBUG: About to insert trimmed item: '" .. tostring(trimmed_item) .. "' into container.")
        table.insert(container, trimmed_item)
        print("DEBUG: Successfully inserted. Container now has " .. #container .. " items.")
    end
    print("DEBUG: gmatch loop finished. Final container: " .. tostring(container) .. ", length: " .. #container)
    return container
end

local function parseIniFile(filename)
    print("DEBUG: parseIniFile called with filename: " .. tostring(filename))
    local file = io.open(filename, "r")
    if not file then
        print("INI Parser: Warning - Config file '" .. filename .. "' not found.")
        return {}
    end

    local config = {}
    local currentSection = nil
    local line_num = 0

    for line in file:lines() do
        line_num = line_num + 1
        print("DEBUG: Processing line " .. line_num .. ": " .. line)
        local trimmed_line = trim(line)

        if trimmed_line ~= "" and not trimmed_line:match("^;") then
            local sectionMatch = trimmed_line:match("^%[([^%]]+)%]$")
            if sectionMatch then
                print("DEBUG: Found section: " .. sectionMatch)
                currentSection = trim(sectionMatch)
                config[currentSection] = config[currentSection] or {}
            else
                local key, value = trimmed_line:match("^([%w_]+)%s*=%s*(.*)$")
                if key and value then
                    print("DEBUG: Found key-value: " .. key .. " = " .. value)
                    if currentSection then
                        -- Identify list-type keys based on naming convention
                        if key:match("Strings$") or key:match("classes$") or key:match("params$") or key:match("accounts$") then
                            print("DEBUG: Key '" .. key .. "' identified as list type. Calling parseList with value: '" .. value .. "'")
                            -- Assign the *result* of parseList(value) (which is a fresh table) to the config key
                            config[currentSection][key] = parseList(value)
                            print("DEBUG: parseList returned for key '" .. key .. "': " .. tostring(config[currentSection][key]))
                            print("DEBUG: Type of config[" .. currentSection .. "][" .. key .. "] is: " .. type(config[currentSection][key]))
                        else
                            local numValue = tonumber(value)
                            config[currentSection][key] = (numValue ~= nil) and numValue or value
                            print("DEBUG: Assigned scalar value '" .. config[currentSection][key] .. "' (type: " .. type(config[currentSection][key]) .. ") to " .. currentSection .. "." .. key)
                        end
                    else
                        print("INI Parser: Warning - Key '" .. key .. "' outside of a section in '" .. filename .. "' (line " .. line_num .. ")")
                    end
                else
                    print("INI Parser: Warning - Could not parse line " .. line_num .. " in '" .. filename .. "': " .. line)
                end
            end
        else
            print("DEBUG: Skipping empty or comment line " .. line_num .. ": " .. line)
        end
    end

    file:close()
    print("DEBUG: parseIniFile finished. Final config structure: " .. tostring(config))
    return config
end

return parseIniFile