dofile (getScriptPath() .. "\\quik_table_wrapper.lua")
dofile (getScriptPath() .. "\\ntime.lua")
stopped = false
function format1(data)
	return string.format("0x%08X", data)
end

function format2(data)
	return string.format("%.2f", data)
end

function format0(data)
	return string.format("%.0f", data)
end

function OnStop(s)
	stopped = true
end

function main()
	-- поворачивающиеся «палочки» в заголовке таблицы
	local palochki = {"-","\\", "|", "/"}
	-- создать экземпляр QTable
	t = QTable.new()
	if not t then
		message("error!", 3)
		return
	else
		message("table with id = " ..t.t_id .. " created", 1)
	end
	
	
	-- добавить два столбца с функциями форматирования
	-- в первом столбце – hex-значения, во втором – целые числа
	-- добавить столбцы без форматирования
	t:AddColumn("ISIN", QTABLE_CACHED_STRING_TYPE, 14)
	t:AddColumn("S_Name", QTABLE_CACHED_STRING_TYPE, 14)
	t:AddColumn("Nominal", QTABLE_INT_TYPE, 9, format2)
	t:AddColumn("Bid", QTABLE_DOUBLE_TYPE, 7, format2)
	t:AddColumn("Offer", QTABLE_DOUBLE_TYPE, 7, format2)
	t:AddColumn("2Mate", QTABLE_INT_TYPE, 4, format0)
	t:AddColumn("2offer", QTABLE_INT_TYPE, 4, format0)
	t:AddColumn("offer", QTABLE_CACHED_STRING_TYPE, 10)
	t:AddColumn("period", QTABLE_INT_TYPE, 3, format0)
	t:AddColumn("Cpn", QTABLE_DOUBLE_TYPE, 5, format2)
	t:AddColumn("Volume", QTABLE_INT_TYPE, 11, format0)
	t:AddColumn("YYcpn", QTABLE_INT_TYPE, 5, format2)
	t:AddColumn("YY2mate", QTABLE_INT_TYPE, 5, format2)
	t:AddColumn("YY2offer", QTABLE_INT_TYPE, 5, format2)
	t:AddColumn("shareprc", QTABLE_DOUBLE_TYPE, 5, format2)
	t:AddColumn("subrd", QTABLE_CACHED_STRING_TYPE, 3)
	t:AddColumn("unit", QTABLE_CACHED_STRING_TYPE, 3)
	t:AddColumn("class", QTABLE_CACHED_STRING_TYPE, 9)
	t:AddColumn("ISIN2", QTABLE_CACHED_STRING_TYPE, 14)
	t:AddColumn("class2", QTABLE_CACHED_STRING_TYPE, 9)
	--t:AddColumn("test4", QTABLE_TIME_TYPE, 50)
	--t:AddColumn("test5", QTABLE_CACHED_STRING_TYPE, 50)
	
	t:SetCaption("Test")
	t:Show()
	i=1
	
	--input csv
	offer_dates = {}	
	for line in io.lines("BONDS2OFFER.csv") do
		local d2OFFER,Yyreal,n,time,s_name,zero,start,finish,y_t_f,YY,Yycpn,Yycpn_real,price,Vol,Cpn,Cpnpery,NKD,Duration,Date_cpn,offer_date,plus1,plus2 = line:match("%s*(.-),%s*(.-),%s*(.-),%s*(.-),%s*(.-),%s*(.-),%s*(.-),%s*(.-),%s*(.-),%s*(.-),%s*(.-),%s*(.-),%s*(.-),%s*(.-),%s*(.-),%s*(.-),%s*(.-),%s*(.-),%s*(.-),%s*(.-),%s*(.-),%s*(.*)")
		offer_dates[s_name] = offer_date
	end

	
	--цикл bonds_yy.qpl (load)
	strBondsClassesList = {"TQCB", "TQOY","TQOB"} --"TQOY","TQOE","TQOD","TQOB","TQIR","TQCB","SPBRUBND","SPBBND"}
	numDays2offer = 0
	numYY_Offer = 0
	for _, strClass in ipairs(strBondsClassesList) do
		for strTickerSecCode in string.gmatch(getClassSecurities(strClass), "([^,]+)") do				
			numBid = tonumber(getParamEx(strClass, strTickerSecCode, "Bid").param_value)
			numBestOffer = tonumber(getParamEx(strClass, strTickerSecCode, "Offer").param_value)
			numNominal = tonumber(getSecurityInfo(strClass, strTickerSecCode).face_value)
			num2Mate = tonumber(getParamEx(strClass, strTickerSecCode, "DAYS_TO_MAT_DATE").param_value)
			numPeriod = tonumber(getParamEx(strClass, strTickerSecCode, "COUPONPERIOD").param_value)
			numCpn = tonumber(getParamEx(strClass, strTickerSecCode, "COUPONVALUE").param_value)
			if numPeriod == 0 then
				numPeriod = 365
			end	
			--numYYcpn = tonumber(getParamEx(strClass, strTickerSecCode, "YIELD").param_value)
			if numBestOffer == 0 then
				numBestOffer = tonumber(getParamEx(strClass, strTickerSecCode, "PREVPRICE").param_value)
			end
			cpnDay = numPeriod / numCpn
			cpnPrft = num2Mate / cpnDay
			pricePrft = (100 - numBestOffer ) * numNominal / 100
			sumProfit = cpnPrft + pricePrft
			
			nomoffer = numNominal * numBestOffer / 10000
			numYYmate = sumProfit / nomoffer / num2Mate * 365

			numYYCpn = 365  / cpnDay / nomoffer
			--numYYmate = ( num2Mate  / numPeriod * numCpn + (100 - numBestOffer ) * numNominal ) / numNominal / numBestOffer / num2Mate  * 365 * 100
			
			
			shareproc = getBuySellInfo("MC0061900000", "25D0D/25D0D", strClass, strTickerSecCode, 0).share
			if shareproc == nil then
				shareproc = 0
			end
						
			
			
			strSName = getSecurityInfo(strClass, strTickerSecCode).short_name			
			if offer_dates[strSName] then
				datetime = {}
				datetime.year, datetime.month, datetime.day = string.match(offer_dates[strSName], "(%d%d%d%d)-(%d%d)-(%d%d)")
			--numDays2offer = tonumber(string.format("%.0f", (os.time(datetime)-os.time())/60/60/24))
				numDays2offer = (os.time(datetime)-os.time())/60/60/24
				cpnPrft = numDays2offer / cpnDay
				sumProfit = cpnPrft + pricePrft
				numYY_Offer = sumProfit / nomoffer / numDays2offer * 365
				
				--numYY_Offer = ( numDays2offer / numPeriod * numCpn + (100 - numBestOffer ) * numNominal ) / numNominal / numBestOffer / numDays2offer * 365 * 100
			else
				numDays2offer = 0
				numYY_Offer = 0
				
			end			

			
			row = t:AddLine()
			t:SetValue(row, "S_Name", strSName)
			t:SetValue(row, "ISIN", getSecurityInfo(strClass, strTickerSecCode).isin_code)
			t:SetValue(row, "Bid", numBid)
			t:SetValue(row, "Offer", numBestOffer)
			t:SetValue(row, "unit", getSecurityInfo(strClass, strTickerSecCode).face_unit)
			t:SetValue(row, "2Mate", num2Mate)
			t:SetValue(row, "2offer", numDays2offer)
			t:SetValue(row, "offer", offer_dates[strSName])
			t:SetValue(row, "period", numPeriod)
			t:SetValue(row, "Cpn", numCpn)
			t:SetValue(row, "Volume", tonumber(getParamEx(strClass, strTickerSecCode, "VOLTODAY").param_value))
			t:SetValue(row, "YY2mate", numYYmate)
			t:SetValue(row, "YY2offer", numYY_Offer)
			t:SetValue(row, "subrd", getParamEx(strClass, strTickerSecCode, "SUBORDINATEDINST").param_image)
			t:SetValue(row, "class", strClass)
			t:SetValue(row, "Nominal", numNominal)
			t:SetValue(row, "YYcpn", numYYCpn)
			t:SetValue(row, "shareprc", tonumber(shareproc))
			
		
		end	
	end
	-- исполнять цикл, пока пользователь не остановит скрипт из диалога управления
	while not stopped do 
	-- если таблица закрыта, то показать ее заново
	-- при этом все предыдущие данные очищаются
	if t:IsClosed() then
		t:Show()
		--GetAll()
	end
		-- на каждой итерации повернуть «палочку» на 45 градусов
		t:SetCaption("QLUA all BND YY " .. palochki[i%4 +1])
		-- метод добавит в таблицу новую строчку и вернет ее номер
		--row = t:AddLine()
		--t:SetValue(row, "S_Name", row, i)
		--t:SetValue(row, "ISIN", row, i)

		--_date = os.date("*t")
		-- 4-й столбец заполнить данными типа время (число в формате <ЧЧММСС>)
		-- Функция для строкового представления времени определена в файле ntime.lua
		-- Функция NiceTime возвращает строку
		--SetCell(t.t_id, row, 4, 
		--NiceTime(_date) .. string.format(" (%02d:%02d:%02d)", _date.hour, _date.min, _date.sec),
		--_date.hour*10000+_date.min*100 +_date.sec)
		-- пятый столбец имеет строковый тип и заполняется результатом выполнения функции NiceTime
		-- исходный код функции взят из виджета Conky Lua для Ubuntu
		--SetCell(t.t_id, row, 5, NiceTime(_date))
		
		-- заполнить ячейку текущим заголовком таблицы
		-- тип столбца – строковый, поэтому последний параметр пропускается
		--SetCell(t.t_id, row, 3, GetWindowCaption(t.t_id))
		
		--GetAll()
		
		sleep(1000)
		i=i+1
	end
	--message("finished")
end
