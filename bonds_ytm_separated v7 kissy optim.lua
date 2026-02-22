dofile (getScriptPath() .. "\\quik_table_wrapper.lua")
dofile (getScriptPath() .. "\\ntime.lua")


-- OPTIMIZATION: Precompile format functions
local format_int = function(v) return string.format("%.0f", v or 0) end
local format_dec2 = function(v) return string.format("%.2f", v or 0) end


-- OPTIMIZATION: Single logging function
local function logMessage(msg, level)
    if type(message) == "function" then
        message(msg, level or 1)
    end
end


-- OPTIMIZATION: Fast number conversion with type check first
local toNumber = function(val, default)
    if val == nil then return default or 0 end
    if type(val) == "number" then return val end
    local num = tonumber(val)
    return num or default or 0
end


-- Parse INI once and store as local variables
local parseIniFile = dofile(getScriptPath() .. "\\ini_parser.lua")
-- Load configuration from INI
local iniConfig = parseIniFile(getScriptPath() .. "\\config_2buy.ini")
--local iniConfig = parseIniFile(getScriptPath() .. "\\config_2sell.ini")

-- Store config in local variables for fast access
local CONFIG_FIRMID = iniConfig.Core.firmID or "00000"
local CONFIG_ACCOUNTS = iniConfig.Core.accounts or {"LWY", "UGC"} -- Should be a list from the parser
local CONFIG_CB = toNumber(iniConfig.BondCalculation.cb, 16)
local CONFIG_RUON = toNumber(iniConfig.BondCalculation.ruon, 16.1)


-- Pre-calculate filter values
local FILTERS = {
    maxBidPrice = toNumber(iniConfig.Filters.maxBidPrice, 102.75),
    minOffers = toNumber(iniConfig.Filters.minOffers, 1),
    minDuration = toNumber(iniConfig.Filters.minDuration, 0),
    maxDuration = toNumber(iniConfig.Filters.maxDuration, 10000),
    minNum2Mate = toNumber(iniConfig.Filters.minNum2Mate, 500),
    maxNum2Mate = toNumber(iniConfig.Filters.maxNum2Mate, 10000),
    minNumYTF = toNumber(iniConfig.Filters.minNumYTF, 18),
    maxNumYTF = toNumber(iniConfig.Filters.maxNumYTF, 29),
    minShareproc = toNumber(iniConfig.Filters.minShareproc, 0),
    maxShareproc = toNumber(iniConfig.Filters.maxShareproc, 3),
    minNumYYCpn = toNumber(iniConfig.Filters.minNumYYCpn, 7),
    maxNumYYCpn = toNumber(iniConfig.Filters.maxNumYYCpn, 1000),
    minNumPL = toNumber(iniConfig.Filters.minNumPL, -1000),
    maxNumPL = toNumber(iniConfig.Filters.maxNumPL, 1000),
    minNumVol = toNumber(iniConfig.Filters.minNumVol, 0),
    maxNumVol = toNumber(iniConfig.Filters.maxNumVol, 99999999),
}


-- OPTIMIZATION: Pre-process string filters to lowercase arrays for faster matching
local function prepareStringFilters(strList)
    if type(strList) == "string" then
        local result = {}
        for str in strList:gmatch("[^,%s]+") do
            if str and str ~= "" then
                table.insert(result, str:lower())
            end
        end
        return result
    elseif type(strList) == "table" then
        local result = {}
        for _, str in ipairs(strList) do
            if str and str ~= "" then
                table.insert(result, str:lower())
            end
        end
        return result
    end
    return {}
end


local EXCLUDE_SNAME = prepareStringFilters(iniConfig.Filters.excludeSNameStrings or {})
local INCLUDE_SNAME = prepareStringFilters(iniConfig.Filters.includeSNameStrings or {})
local EXCLUDE_COMMENT = prepareStringFilters(iniConfig.Filters.excludeCommentStrings or {})
local INCLUDE_COMMENT = prepareStringFilters(iniConfig.Filters.includeCommentStrings or {})
local INCLUDE_CURRENCY = prepareStringFilters(iniConfig.Filters.includeCurrencyStrings or {})
local EXCLUDE_CURRENCY = prepareStringFilters(iniConfig.Filters.excludeCurrencyStrings or {})


-- Store other configs
local SECURITY_CLASSES = iniConfig.SecurityClasses.classes or
                         {"TQOY","TQOE","TQOD","TQOB","TQIR","TQCB","SPBRUBND","SPBBND","TQRD"}


-- Fallback parameters for price data
local FALLBACK_PARAMS = iniConfig.FallbackParams.params or 
                        {"PREVPRICE", "WAPRICE", "LCLOSEPRICE", "LCURRENTPRICE"}
local DEFAULT_PERIOD = 365
local DEFAULT_NOMINAL = 1000


-- Overrides
local PERIOD_OVERRIDES = {
    ["RU000A107A69"] = 153,
    ["RU000A107670"] = 149,
    ["RU000A0JXTY7"] = 182,
    ["RU000A1008J4"] = 182,
    ["RU000A100FE5"] = 91,
    ["RU000A100N12"] = 182,
    ["XS0559915961"] = 184
}


local YYCPN_OVERRIDES = {
    --["XS0114288789"] = 7.5
}


export_results = toNumber(iniConfig.General.export_results, 1)
stopped = false


-- Fast string utilities
local trim = function(s)
    if type(s) ~= "string" then return s end
    --return s:match("^%s(.-)%s$") or s
    return s:match("^%s*(.-)%s*$") or s
end


-- Pre-compiled patterns
local CSV_PATTERN = "([^;]*)"
local DATE_PATTERN = "(%d%d)%.(%d%d)%.(%d%d%d%d)"


-- Fast contains check with pre-lowered strings
local function containsAnyFast(str, filterArray)
    if not str or type(str) ~= "string" or #filterArray == 0 then return false end
    local str_lower = str:lower()
    for i = 1, #filterArray do
        if str_lower:find(filterArray[i], 1, true) then
            return true
        end
    end
    return false
end


-- Check if string contains all of the substrings
local function containsAllFast(str, filterArray)
    if not str or type(str) ~= "string" or #filterArray == 0 then return true end
    local str_lower = str:lower()
    for i = 1, #filterArray do
        if not str_lower:find(filterArray[i], 1, true) then
            return false
        end
    end
    return true
end


-- Safe QUIK API wrapper with minimal overhead
local function safeQuikCall(func, ...)
    return func(...)
end


-- Compile coupon formula
local function compileCouponFormula(formulaStr, ticker)
    if not formulaStr or formulaStr == "" then return nil end

    -- Extract formula part (before any slash which might indicate comment)
    local formulaPart = formulaStr:match("^([%w_%-%+%.]+%s*[%-%+*/%s%w_%-%.%(%)^]*)") or formulaStr

    -- Check if it's actually a formula (contains operators)
    if not formulaPart:find("[%+%-/%*%^]") then
        return nil
    end

    -- Create a safe environment with only allowed variables and math functions
    local env = { cb = nil, ruon = nil, math = math }
    local func, err = load("return " .. formulaPart, "coupon_formula", "t", env)

    if not func then
        logMessage("Failed to compile formula for " .. ticker .. ": " .. err, 2)
        return nil
    end

    return function(cbValue, ruonValue)
        env.cb = cbValue
        env.ruon = ruonValue
        return func()
    end

end


-- Fast file operations
local function writeCSV(filename, data, headers)
    local file = io.open(filename, "w")
    if not file then 
        logMessage("Failed to write file: " .. filename, 2)
        return 
    end

    file:write(table.concat(headers, ";") .. "\n")
    for i = 1, #data do
        local row = data[i]
        local rowStr = {}
        for j = 1, #headers do
            local header = headers[j]
            local val = row[header] or ""
            if type(val) == "number" then
                if header == "nBids" or header == "nOffers" or header == "2Mate" 
                   or header == "2offer" or header == "period" or header == "Duration" 
                   or header == "Volume" then
                    val = format_int(val)
                else
                    val = "'" .. tostring(val)
                end
            end
            val = tostring(val):gsub(";", ";;")
            rowStr[j] = val
        end
        file:write(table.concat(rowStr, ";") .. "\n")
    end
    file:close()

end


-- Efficient bond data loader
local function loadBondsData(filename)
    local file = io.open(filename, "r")
    if not file then
        logMessage("Failed to open bonds data file", 2)
        return {}
    end

    file:read("*line") -- Skip header
    local data = {}

    for line in file:lines() do
        local fields = {}
        for val in line:gmatch(CSV_PATTERN) do
            fields[#fields + 1] = trim(val)
        end

    -- New structure: fields[1] = strSName, fields[2] = isin
    local strSName = fields[1]
    local isin = fields[2]
    if isin and isin ~= "" then
        local comment = fields[3] or ""
        local formula = fields[4] or ""
        local offer_date = fields[5] or ""
        data[isin] = {
            strSName = strSName,
            isin = isin,
            comment = comment,
            formula = formula,
            compiled_formula = compileCouponFormula(formula, isin),
            offer_date = offer_date
        }
    end
    end
    file:close()
    return data

end


-- Security cache with LRU-like eviction
local securityCache = {}
local function getSecurityInfoCached(class, ticker)
    local key = class .. ":" .. ticker
    local cached = securityCache[key]
    if cached then return cached end

    cached = getSecurityInfo(class, ticker) or {}
    securityCache[key] = cached
    return cached

end


-- Bond calculation with pre-calculated constants
local BondCalculator = {}


function BondCalculator.calculateDaysToDate(dateStr)
    if not dateStr or dateStr == "" then return 0 end

    local day, month, year = dateStr:match(DATE_PATTERN)
    if not day then return 0 end

    local offerTime = os.time({day=tonumber(day), month=tonumber(month), year=tonumber(year)})
    return math.floor((offerTime - os.time()) / 86400) --return days in seconds 24 * 60 * 60

end


function BondCalculator.calculateCouponFromCompiledFormula(compiled_func)
    if not compiled_func then return nil end
    local success, result = pcall(compiled_func, CONFIG_CB, CONFIG_RUON)
    return success and result or nil
end


-- Fast param fetch with cache
local paramCache = {}
function BondCalculator.getParam(class, ticker, param, fallbacks)
    local key = class .. ":" .. ticker .. ":" .. param
    local cached = paramCache[key]
    if cached ~= nil then return cached end

    local value = 0
    local paramResult = getParamEx(class, ticker, param)
    if paramResult then
        value = toNumber(paramResult.param_value)
    end

    if value ~= 0 then
        paramCache[key] = value
        return value
    end

    if fallbacks then
        for i = 1, #fallbacks do
            local fallback = fallbacks[i]
            local fallbackKey = class .. ":" .. ticker .. ":" .. fallback
            local fallbackValue = paramCache[fallbackKey]

            if fallbackValue == nil then
                local fallbackResult = getParamEx(class, ticker, fallback)
                if fallbackResult then
                    fallbackValue = toNumber(fallbackResult.param_value)
                else
                    fallbackValue = 0
                end
                paramCache[fallbackKey] = fallbackValue
            end

            if fallbackValue ~= 0 then
                paramCache[key] = fallbackValue
                return fallbackValue
            end
        end
    end

    paramCache[key] = 0
    return 0

end


function BondCalculator.calculateYields(bondData)
    -- Use weighted average price if available, otherwise use bid
    local numMarketPrice
    if bondData.numOffer == 0 then
        numMarketPrice = bondData.numBid
    else
        numMarketPrice = (bondData.numOffer * 2 + bondData.numBid) / 3
    end


    local tempBid = numMarketPrice / bondData.numNominal
    local couponToUse = bondData.calculatedCpn or bondData.numCpn
    local numYYCpn = 365 / bondData.numPeriod * couponToUse / tempBid / 100

    local override = YYCPN_OVERRIDES[bondData.ticker]
    if override then
        numYYCpn = override
    end

    -- Calculate Yield to Maturity (YTM)
    local numYTF
    if bondData.num2Mate > 365 and bondData.numOffer ~= 0 then
        numYTF = numYYCpn + bondData.numNominal * (1 / tempBid - bondData.numNominal/100)/100 / bondData.num2Mate * 365
    else
        local nominalPriceCoef = bondData.numNominal * numMarketPrice / 10000
        -- Avoid division by zero if nominalPriceCoef is 0
        if nominalPriceCoef == 0 then
            numYTF = 0
        else
            numYTF = math.floor((bondData.num2Mate / bondData.numPeriod * couponToUse +
                               (100 - numMarketPrice) * bondData.numNominal / 100) /
                               bondData.num2Mate * 365) / nominalPriceCoef
        end
    end

    -- Calculate Yield to Offer (numYTO) - simplified
    local numYTO = 0
    -- Only calculate YTO if num2offer is positive and numOffer is available
    if bondData.num2offer > 0 and bondData.numOffer ~= 0 then
        -- Very simple approximation: use the same logic as YTF but for offer date
        local offerPricePer100 = bondData.numOffer / (bondData.numNominal / 100)
        if offerPricePer100 > 0 then
            -- Simple yield calculation: annual coupon yield + capital gain annualized
            local capitalGainPerYear = ((100 - offerPricePer100) / bondData.num2offer) * 365 / 100
            numYTO = numYYCpn + capitalGainPerYear
        end
    end

    return numYYCpn, numYTF, numYTO, numMarketPrice

end


-- Bond filter with pre-compiled predicates
local BondFilter = {
    predicates = {}  -- Store only predicate functions
}


function BondFilter:initializeFilters()
    -- Clear existing filters
    self.predicates = {}


    -- Price filter
    table.insert(self.predicates, function(bond)
        return bond.numBid < FILTERS.maxBidPrice
    end)

    -- Liquidity filter
    table.insert(self.predicates, function(bond)
        return bond.nOffers > FILTERS.minOffers
    end)

    -- Subordination filter
    table.insert(self.predicates, function(bond)
        return bond.strSub ~= 'Да'
    end)

    -- Duration range filter
    table.insert(self.predicates, function(bond)
        return bond.numDuration >= FILTERS.minDuration and
               bond.numDuration <= FILTERS.maxDuration
    end)

    -- Days to maturity filter
    table.insert(self.predicates, function(bond)
        return bond.num2Mate >= FILTERS.minNum2Mate and
               bond.num2Mate <= FILTERS.maxNum2Mate
    end)

    -- YTF filter
    table.insert(self.predicates, function(bond)
        return bond.numYTF >= FILTERS.minNumYTF and
               bond.numYTF <= FILTERS.maxNumYTF
    end)

    -- Portfolio share filter
    table.insert(self.predicates, function(bond)
        return bond.shareproc >= FILTERS.minShareproc and
               bond.shareproc <= FILTERS.maxShareproc
    end)

    -- YYCpn filter
    table.insert(self.predicates, function(bond)
        return bond.numYYCpn >= FILTERS.minNumYYCpn and
               bond.numYYCpn <= FILTERS.maxNumYYCpn
    end)

    -- P&L filter
    table.insert(self.predicates, function(bond)
        return bond.numPL >= FILTERS.minNumPL and
               bond.numPL <= FILTERS.maxNumPL
    end)

    -- Volume filter
    table.insert(self.predicates, function(bond)
        local numVol = toNumber(bond.numVol)
        return numVol >= FILTERS.minNumVol and
               numVol <= FILTERS.maxNumVol
    end)

    -- Exclude SName strings filter
    if #EXCLUDE_SNAME > 0 then
        table.insert(self.predicates, function(bond)
            return not containsAnyFast(bond.strSName, EXCLUDE_SNAME)
        end)
    end

    -- Include SName strings filter
    if #INCLUDE_SNAME > 0 then
        table.insert(self.predicates, function(bond)
            return containsAllFast(bond.strSName, INCLUDE_SNAME)
        end)
    end

    -- Exclude comment strings filter
    if #EXCLUDE_COMMENT > 0 then
        table.insert(self.predicates, function(bond)
            return not containsAnyFast(bond.fullComment, EXCLUDE_COMMENT)
        end)
    end

    -- Include comment strings filter
    if #INCLUDE_COMMENT > 0 then
        table.insert(self.predicates, function(bond)
            return containsAllFast(bond.fullComment, INCLUDE_COMMENT)
        end)
    end

    -- Include currency strings filter
    if #INCLUDE_CURRENCY > 0 then
        table.insert(self.predicates, function(bond)
            return containsAnyFast(bond.strUnit, INCLUDE_CURRENCY)
        end)
    end

    -- Exclude currency strings filter
    if #EXCLUDE_CURRENCY > 0 then
        table.insert(self.predicates, function(bond)
            return not containsAnyFast(bond.strUnit, EXCLUDE_CURRENCY)
        end)
    end

end


function BondFilter:apply(bondData)
    for i = 1, #self.predicates do
        if not self.predicates[i](bondData) then
        --if not self.predicatesi then
            return false
        end
    end
    return true
end


-- Portfolio cache with TTL
local portfolioCache = {}
local portfolioCacheTimes = {}
local CACHE_TTL = 60


local function calculatePortfolioShare(class, ticker)
    local key = CONFIG_FIRMID .. ":" .. class .. ":" .. ticker
    local now = os.time()


    -- Check cache
    local cached = portfolioCache[key]
    if cached and (now - portfolioCacheTimes[key]) < CACHE_TTL then
        return cached.totalShare, cached.numBalPrice
    end

    local totalShare = 0
    local numBalPrice = 0

    for i = 1, #CONFIG_ACCOUNTS do
        local account = CONFIG_ACCOUNTS[i]
        local share_info = getBuySellInfo(CONFIG_FIRMID, account, class, ticker, 0)
        if share_info then
            local share = toNumber(share_info.share)
            totalShare = totalShare + share

            if share > 0 and numBalPrice == 0 then
                numBalPrice = toNumber(share_info.long_wa_price)
            end
        end
    end

    local data = { totalShare = totalShare, numBalPrice = numBalPrice }
    portfolioCache[key] = data
    portfolioCacheTimes[key] = now

    return totalShare, numBalPrice

end


-- Table renderer - FIXED: Proper initialization
local TableRenderer = {
    instance = nil,
    userData = {},
    columnIndices = {}
}


function TableRenderer:initialize()
    -- Check if QTable exists
    if not QTable then
        logMessage("QTable module not available", 3)
        return nil
    end


    -- Create table instance
    local instance = QTable.new()
    if not instance then
        logMessage("Failed to create QTable instance", 2)
        return nil
    end

    self.instance = instance
    self.userData = {}

    -- Add columns with EXACT names that will be used in SetValue
    instance:AddColumn("ISIN", QTABLE_CACHED_STRING_TYPE, 16)
    instance:AddColumn("S_Name", QTABLE_CACHED_STRING_TYPE, 14)
    instance:AddColumn("Nominal", QTABLE_INT_TYPE, 5, format_int)
    instance:AddColumn("Bid", QTABLE_DOUBLE_TYPE, 7, format_dec2)
    instance:AddColumn("Offer", QTABLE_DOUBLE_TYPE, 7, format_dec2)
    instance:AddColumn("BalPrice", QTABLE_DOUBLE_TYPE, 7, format_dec2)
    instance:AddColumn("PL", QTABLE_DOUBLE_TYPE, 6, format_dec2)
    instance:AddColumn("nBids", QTABLE_INT_TYPE, 5, format_int)
    instance:AddColumn("nOffers", QTABLE_INT_TYPE, 5, format_int)
    instance:AddColumn("2Mate", QTABLE_INT_TYPE, 5, format_int)
    instance:AddColumn("2offer", QTABLE_INT_TYPE, 4, format_int)
    instance:AddColumn("offer_date", QTABLE_CACHED_STRING_TYPE, 10)
    instance:AddColumn("period", QTABLE_INT_TYPE, 3, format_int)
    instance:AddColumn("Cpn", QTABLE_DOUBLE_TYPE, 5, format_dec2)
    instance:AddColumn("Volume", QTABLE_INT_TYPE, 9, format_int)
    instance:AddColumn("Duration", QTABLE_INT_TYPE, 5, format_int)
    instance:AddColumn("YY2offer", QTABLE_DOUBLE_TYPE, 6, format_dec2)
    instance:AddColumn("YYcpn", QTABLE_DOUBLE_TYPE, 6, format_dec2)
    instance:AddColumn("YY2mate", QTABLE_DOUBLE_TYPE, 6, format_dec2)
    instance:AddColumn("shareprc", QTABLE_DOUBLE_TYPE, 5, format_dec2)
    instance:AddColumn("subrd", QTABLE_CACHED_STRING_TYPE, 3)
    instance:AddColumn("unit", QTABLE_CACHED_STRING_TYPE, 3)
    instance:AddColumn("class", QTABLE_CACHED_STRING_TYPE, 7)
    instance:AddColumn("Notes", QTABLE_CACHED_STRING_TYPE, 20)


    -- Add columns and store indices
    --for i, col in ipairs(columns) do
    --    instance:AddColumn(col[1], col[2], col[3])
    --    self.columnIndices[col[1]] = i
    --end

    instance:SetCaption("Bonds YTM Scanner v7.0")
    instance:Show()

    return instance

end


function TableRenderer:addBondRow(bondData)
    if not self.instance then
        logMessage("ERROR: No table instance", 2)
        return nil
    end


    local row = self.instance:AddLine()
    if not row then
        logMessage("ERROR: Failed to add line", 2)
        return nil
    end

    -- DEBUG: Check what columns exist
    --logMessage("Adding bond: " .. (bondData.ticker or "unknown"), 1)
    -- Use column NAMES not indices for QTable wrapper
    self.instance:SetValue(row, "2Mate", bondData.num2Mate or 0)
    self.instance:SetValue(row, "2offer", bondData.num2offer or 0)
    self.instance:SetValue(row, "BalPrice", bondData.numBalPrice or 0)
    self.instance:SetValue(row, "Bid", bondData.numBid or 0)
    self.instance:SetValue(row, "Cpn", bondData.numCpn or 0)
    self.instance:SetValue(row, "Duration", bondData.numDuration or 0)
    self.instance:SetValue(row, "ISIN", bondData.isin or "")
    self.instance:SetValue(row, "Nominal", bondData.numNominal or 0)
    self.instance:SetValue(row, "Notes", bondData.fullComment or "")
    self.instance:SetValue(row, "Offer", bondData.numOffer or 0)
    self.instance:SetValue(row, "PL", bondData.numPL or 0)
    self.instance:SetValue(row, "S_Name", bondData.strSName or "")
    self.instance:SetValue(row, "Volume", bondData.numVol or 0)
    self.instance:SetValue(row, "YY2mate", bondData.numYTF or 0)
    self.instance:SetValue(row, "YY2offer", bondData.numYTO or 0)
    self.instance:SetValue(row, "YYcpn", bondData.numYYCpn or 0)
    self.instance:SetValue(row, "class", bondData.strClass or "")
    self.instance:SetValue(row, "nBids", bondData.nBids or 0)
    self.instance:SetValue(row, "nOffers", bondData.nOffers or 0)
    self.instance:SetValue(row, "offer_date", bondData.offer_date or "")
    self.instance:SetValue(row, "period", bondData.numPeriod or 0)
    self.instance:SetValue(row, "shareprc", bondData.shareproc or 0)
    self.instance:SetValue(row, "subrd", bondData.strSub or "")
    self.instance:SetValue(row, "unit", bondData.strUnit or "")


    -- Store reference in our own cache if QTable fails
    self.userData[row] = bondData.strClass .. ":" .. bondData.ticker
    return row

end


-- Main analyzer with memory-efficient data structures
local BondAnalyzer = {
    stopped = false,
    bondsData = nil,
    filter = nil,
    tableRenderer = nil,
    exportResults = nil,
    missingDataLog = nil,
    displayedSecurities = nil,
    bondsDataUpdatedNames = false
}


function BondAnalyzer:initialize()


    -- Load data only once
    if not self.bondsData then
        self.bondsData = loadBondsData(getScriptPath() .. "\\bonds_data_sname.csv")
        self.bondsDataUpdatedNames = false
    end

    self.filter = BondFilter
    self.filter:initializeFilters()

    -- Initialize table renderer
    self.tableRenderer = TableRenderer
    local tableInstance = self.tableRenderer:initialize()

    if not tableInstance then
        logMessage("Table initialization failed, continuing without table display", 2)
    end

    -- Pre-allocate arrays
    self.exportResults = {}
    self.missingDataLog = {}
    self.displayedSecurities = {}

end


function BondAnalyzer:processSecurity(strClass, strTickerSecCode)


    -- Fast parameter fetching
    local numBid = BondCalculator.getParam(strClass, strTickerSecCode, "BID")
    local numOffer = BondCalculator.getParam(strClass, strTickerSecCode, "OFFER", FALLBACK_PARAMS)
    if numBid == 0 then numBid = numOffer end

    local securityInfo = getSecurityInfoCached(strClass, strTickerSecCode)
    local numNominal = toNumber(securityInfo.face_value, DEFAULT_NOMINAL)
    local numCpn = BondCalculator.getParam(strClass, strTickerSecCode, "COUPONVALUE")
    local num2Mate = BondCalculator.getParam(strClass, strTickerSecCode, "DAYS_TO_MAT_DATE")
    local numPeriod = BondCalculator.getParam(strClass, strTickerSecCode, "COUPONPERIOD")
    local numDuration = BondCalculator.getParam(strClass, strTickerSecCode, "DURATION")
    local strSName = securityInfo.short_name or "N/A"
    local strUnit = securityInfo.face_unit or "N/A"

    local strSubResult = getParamEx(strClass, strTickerSecCode, "SUBORDINATEDINST")
    local strSub = strSubResult and strSubResult.param_image or ""

    local nOffers = BondCalculator.getParam(strClass, strTickerSecCode, "NUMOFFERS")

    -- Process bonds metadata
    local bond = self.bondsData[strTickerSecCode]
    local fullComment = ""
    local num2offer = 0
    local offer_date = ""
    local calculatedCpn = nil

    if bond then
        fullComment = bond.comment or ""
        offer_date = bond.offer_date or ""

        if bond.compiled_formula or bond.formula then
            -- Use the new formula field if exists
            local formulaToUse = bond.formula or ""
            if bond.compiled_formula then
                local rawCpnValue = BondCalculator.calculateCouponFromCompiledFormula(bond.compiled_formula)
                if rawCpnValue then
                    calculatedCpn = (rawCpnValue / 100) * numNominal * (numPeriod / 365)
                    fullComment = fullComment .. " /flt " .. (bond.formula or "")
                end
            end
            -- If there is no compiled formula but a raw formula, try to compile now
            if (not bond.compiled_formula) and formulaToUse ~= "" then
                local compiled = compileCouponFormula(formulaToUse, strTickerSecCode)
                if compiled then
                    bond.compiled_formula = compiled
                end
            end
        end

        if offer_date ~= "" then
            num2offer = BondCalculator.calculateDaysToDate(offer_date)
        end
    end

    -- Apply period overrides
    numPeriod = PERIOD_OVERRIDES[strTickerSecCode] or (numPeriod == 0 and DEFAULT_PERIOD or numPeriod)

    -- Determine ISIN: Use proper ISIN ticker if it starts with "SU", otherwise use isin_code
    --local finalIsin = securityInfo.isin_code or strTickerSecCode
    --if finalIsin:sub(1, 2) == "SU" then
    --    finalIsin = getParamEx(strClass, strTickerSecCode, "CODE").param_value
    --end
    -- Create bond data as array-like table for memory efficiency
    local bondData = {
        ticker = strTickerSecCode,
        strClass = strClass,
        strSName = strSName,
        isin = strTickerSecCode,
        numBid = numBid,
        numOffer = numOffer,
        numNominal = numNominal,
        numCpn = numCpn,
        calculatedCpn = calculatedCpn,
        num2Mate = num2Mate,
        numPeriod = numPeriod,
        numDuration = numDuration,
        strUnit = strUnit,
        strSub = strSub,
        nOffers = nOffers,
        numVol = BondCalculator.getParam(strClass, strTickerSecCode, "VOLTODAY"),
        nBids = BondCalculator.getParam(strClass, strTickerSecCode, "NUMBIDS"),
        num2offer = num2offer,
        offer_date = offer_date,
        fullComment = fullComment
    }

    local numYYCpn, numYTF, numYTO = BondCalculator.calculateYields(bondData)
    bondData.numYYCpn = numYYCpn
    bondData.numYTF = numYTF
    bondData.numYTO = numYTO

    -- Calculate portfolio data
    bondData.shareproc, bondData.numBalPrice = calculatePortfolioShare(strClass, strTickerSecCode)
    bondData.numPL = bondData.shareproc == 0 and 0 or (bondData.numOffer - bondData.numBalPrice)

    -- Log missing data
    if bondData.numCpn == 0 or bondData.numPeriod == 0 then
        table.insert(self.missingDataLog, {
            S_Name = bondData.strSName,
            ISIN = bondData.isin,
            Volume = bondData.numVol,            
            numPeriod = math.floor(bondData.numPeriod),
            numCpn = bondData.numCpn,
            SourceCpn = calculatedCpn and "bonds_data_sname.csv" or "Server",
            CheckDate = os.date("%d.%m.%Y %H:%M:%S")
        })
    end

    -- Quick reject before full processing if possible
    if not bondData then return false end

    -- If a bond exists in bonds_data_sname.csv, update its strSName if we found a more accurate one
    if bond and (bond.strSName == nil or bond.strSName == "" or bond.strSName ~= (strSName or "")) then
        bond.strSName = strSName
        self.bondsDataUpdatedNames = true
    end

    -- Apply filter
    if self.filter:apply(bondData) then
        displayedCount = displayedCount + 1        
        if self.tableRenderer.instance then
            local row = self.tableRenderer:addBondRow(bondData)
            if row then
                table.insert(self.displayedSecurities, row)
            end
        end

        table.insert(self.exportResults, bondData)
        return true
    end

    return false

end


function BondAnalyzer:processAllSecurities()
    -- Clear caches and data 
    securityCache = {}
    paramCache = {}
    portfolioCache = {}
    portfolioCacheTimes = {}


    self.exportResults = {}
    self.missingDataLog = {}
    self.displayedSecurities = {}
    self.bondsDataUpdatedNames = false

    --for i = 1, #SECURITY_CLASSES do --bad decision
    for i, strClass in ipairs(SECURITY_CLASSES) do
        local strClass = SECURITY_CLASSES[i]
        local securities = getClassSecurities(strClass) or ""

        for strTickerSecCode in securities:gmatch("([^,]+)") do
            strTickerSecCode = trim(strTickerSecCode)
            if strTickerSecCode ~= "" and not self.stopped then
                local ok, err = pcall(function()
                    return self:processSecurity(strClass, strTickerSecCode)
                end)

                if not ok then
                    logMessage("Failed to process " .. strClass .. ":" .. strTickerSecCode .. ": " .. tostring(err), 2)
                end
            end
        end

        if self.stopped then break end
    end

end
function BondAnalyzer:saveUpdatedBondsDataIfNeeded()
    -- Only proceed if names were actually flagged as updated
    if not self.bondsDataUpdatedNames then return end
    -- Rewrite bonds_data_sname.csv with updated strSName values
    local data = self.bondsData or {}
    local filename = getScriptPath() .. "\\bonds_data_sname.csv"
    
    -- 1. Optimization: Collect rows in a temp table for sorting
    local sortedList = {}
    for isin, entry in pairs(data) do
        -- Clean 's' or 'i' at the beginning (case-sensitive)
        local cleanSName = tostring(entry.strSName or ""):gsub("^[si]", "")
        table.insert(sortedList, {
            sName = cleanSName,
            isin = tostring(isin or entry.isin or ""),
            comment = tostring(entry.comment or ""),
            formula = tostring(entry.formula or ""),
            offer = tostring(entry.offer_date or "")
        })
    end

    -- 2. Sort alphabetically by cleanSName
    table.sort(sortedList, function(a, b)
        return a.sName:lower() < b.sName:lower()
    end)

    -- 3. Optimization: Build the entire file content in memory (much faster than multiple f:write)
    local output = {}
    table.insert(output, "strSName;ISIN;comment;formula;offer_date") -- Header
    
    for _, item in ipairs(sortedList) do
        -- Use a simple string format for speed
        local line = string.format("%s;%s;%s;%s;%s", 
            item.sName, item.isin, item.comment, item.formula, item.offer)
        table.insert(output, line)
    end

    -- 4. Single Write Operation
    local f = io.open(filename, "w")
    if f then
        f:write(table.concat(output, "\n") .. "\n")
        f:close()
        
        -- Reset the flag after successful save
        self.bondsDataUpdatedNames = false 
        --logMessage("bonds_data_sname.csv updated and sorted alphabetically.", 1)
    else
        logMessage("Failed to write updated bonds_data_sname.csv", 2)
    end
end


function BondAnalyzer:run()
    startTime = os.clock()
    displayedCount = 0
    -- Initialize
    self:initialize()


    -- Process securities
    self:processAllSecurities()

    -- Update table caption if table exists
    if self.tableRenderer and self.tableRenderer.instance then
        local elapsed = os.clock() - startTime
        self.tableRenderer.instance:SetCaption(string.format("Bonds v7.0: %d (%.1fs)", displayedCount, elapsed))
    end

    -- Write files
    if #self.missingDataLog > 0 then
        writeCSV(getScriptPath() .. "\\missing_data_log.csv",
                self.missingDataLog,
                {"S_Name", "ISIN", "Volume", "numPeriod", "numCpn", "SourceCpn", "CheckDate"})
    end

    -- Export results if enabled
    if export_results == 1 and #self.exportResults > 0 then
        local exportHeaders = {"ISIN", "S_Name", "Nominal", "Bid", "Offer", "BalPrice", "PL", 
                              "nBids", "nOffers", "2Mate", "2offer", "offer_date", "period", 
                              "Cpn", "Volume", "Duration", "YY2offer", "YYcpn", "YY2mate", 
                              "shareprc", "subrd", "unit", "class", "Notes"}

        local exportData = {}
        for i = 1, #self.exportResults do
            local row = self.exportResults[i]
            exportData[i] = {
                ISIN = row.isin,
                S_Name = row.strSName or "",
                Nominal = row.numNominal,
                Bid = row.numBid,
                Offer = row.numOffer,
                BalPrice = row.numBalPrice,
                PL = row.numPL,
                nBids = row.nBids,
                nOffers = row.nOffers,
                ["2Mate"] = row.num2Mate,
                ["2offer"] = row.num2offer,
                offer_date = row.offer_date,
                period = row.numPeriod,
                Cpn = row.numCpn,
                Volume = row.numVol,
                Duration = row.numDuration,
                YY2offer = row.numYTO,
                YYcpn = row.numYYCpn,
                YY2mate = row.numYTF,
                shareprc = row.shareproc,
                subrd = row.strSub,
                unit = row.strUnit,
                class = row.strClass,
                Notes = row.fullComment
            }
        end

        writeCSV(getScriptPath() .. "\\export_results.csv", exportData, exportHeaders)
    end
    -- Persist any updated SNames back to bonds_data_sname.csv
    self:saveUpdatedBondsDataIfNeeded()

end


function BondAnalyzer:stop()
    self.stopped = true
end


-- QUIK Event Handlers
function OnStop(s)
    if bondAnalyzer then
        bondAnalyzer:stop()
    end
    stopped = true
end


function main()
    logMessage("Bond Scanner v7.0 started", 1)


    if not QTable then
        logMessage("QTable module not available", 3)
        return
    end

    bondAnalyzer = {
        stopped = false,
        bondsData = nil,
        filter = BondFilter,
        tableRenderer = TableRenderer,
        exportResults = {},
        missingDataLog = {},
        displayedSecurities = {}
    }

    -- Set metatable to inherit methods
    setmetatable(bondAnalyzer, {__index = BondAnalyzer})

    -- Run with error handling
    local success, err = pcall(function()
        bondAnalyzer:run()
    end)

    if not success then
        logMessage("Error in main: " .. tostring(err), 3)
    end

    logMessage(string.format("Bond Scanner v7.0 finished: %d bonds in %.2f seconds", displayedCount, os.clock() - startTime), 1)

end

