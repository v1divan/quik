words = {"one ", "two ", "three ", "four ", "five ", "six ", "seven ", "eight ", "nine "}
levels = {"thousand ", "million ", "billion ", "trillion ", "quadrillion ", "quintillion ", "sextillion ", "septillion ", "octillion ", [0] = ""}
iwords = {"ten ", "twenty ", "thirty ", "forty ", "fifty ", "sixty ", "seventy ", "eighty ", "ninety "}
twords = {"eleven ", "twelve ", "thirteen ", "fourteen ", "fifteen ", "sixteen ", "seventeen ", "eighteen ", "nineteen "}

function GetAll()
	-- если таблица закрыта, то показать ее заново
	-- при этом все предыдущие данные очищаются
	-- нужно вызвать процедуру loadAll()
	if t:IsClosed() then
		t:Show()
	end
	--цикл bonds_yy.qpl (load)
	n = t:GetSize()
	
	
	

	
	for row_upd_upd=1,n do
		strClass2 = t:GetValue(row_upd_upd, "class").image
		strTickerSecCode2 = t:GetValue(row_upd_upd, "ISIN").image
		--t:SetValue(row_upd_upd, "class2", strClass22)
		--t:SetValue(row_upd_upd, "ISIN2", getSecurityInfo(strClass22, strTickerSecCode22).isin_code)
		
		for strTickerSecCode2 in string.gmatch(getClassSecurities(strClass2), "([^,]+)") do					--if strTickerSecCode2 == "RU000A105P64" then
				--strClass22 = "D"
				--t:SetValue(row_upd_upd, "class2", strClass22)
			--end
			numBid = tonumber(getParamEx(strClass2, strTickerSecCode2, "Bid").param_value)
			numBestOffer = tonumber(getParamEx(strClass2, strTickerSecCode2, "Offer").param_value)
			numNominal = t:GetValue(row_upd_upd, "Nominal").image
			num2Mate = t:GetValue(row_upd_upd, "2Mate").image
			numPeriod = t:GetValue(row_upd_upd, "period").image
			numCpn = t:GetValue(row_upd_upd, "Cpn").image
			
			if numBestOffer == 0 then
				numBestOffer = tonumber(getParamEx(strClass2, strTickerSecCode2, "PREVPRICE").param_value)
			end
			
			cpnDay = numPeriod / numCpn
			cpnPrft = num2Mate / cpnDay
			pricePrft = (100 - numBestOffer ) * numNominal / 100
			sumProfit = cpnPrft + pricePrft
			
			nomoffer = numNominal * numBestOffer / 10000
			numYYmate = sumProfit / nomoffer / num2Mate * 365

			numYYCpn = 365  / cpnDay / nomoffer
			--numYYmate = ( num2Mate  / numPeriod * numCpn + (100 - numBestOffer ) * numNominal ) / numNominal / numBestOffer / num2Mate  * 365 * 100
			
			
			shareproc = getBuySellInfo("MC0061900000", "25D0D/25D0D", strClass2, strTickerSecCode2, 0).share
			if shareproc == nil then
				shareproc = 0
			end
				
			numDays2offer = t:GetValue(row_upd_upd, "2offer").value
			cpnPrft = numDays2offer / cpnDay
			--sumProfit = cpnPrft + pricePrft
			numYY_Offer = sumProfit / nomoffer / numDays2offer * 365
				
				--numYY_Offer = ( numDays2offer / numPeriod * numCpn + (100 - numBestOffer ) * numNominal ) / numNominal / numBestOffer / numDays2offer * 365 * 100

			
			--row_upd = t:AddLine()
			--t:SetValue(row_upd, "S_Name", strSName)
			--t:SetValue(row_upd, "ISIN", getSecurityInfo(strClass2, strTickerSecCode2).isin_code)
			
			
			
	

			
			
			
			
			t:SetValue(row_upd, "Bid", numBid)
			t:SetValue(row_upd, "Offer", numBestOffer)
			--t:SetValue(row_upd, "unit", getSecurityInfo(strClass2, strTickerSecCode2).face_unit)
			t:SetValue(row_upd, "2Mate", num2Mate)
			t:SetValue(row_upd, "2offer", numDays2offer)
			--t:SetValue(row_upd, "offer", offer_dates[strSName])
			--t:SetValue(row_upd, "period", numPeriod)
			--t:SetValue(row_upd, "Cpn", numCpn)
			t:SetValue(row_upd, "Volume", tonumber(getParamEx(strClass2, strTickerSecCode2, "VOLTODAY").param_value))
			t:SetValue(row_upd, "YY2mate", numYYmate)
			t:SetValue(row_upd, "YY2offer", numYY_Offer)
			--t:SetValue(row_upd, "subrd", getParamEx(strClass2, strTickerSecCode2, "SUBORDINATEDINST").param_image)
			--t:SetValue(row_upd, "class", strClass2)
			--t:SetValue(row_upd, "Nominal", numNominal)
			t:SetValue(row_upd, "YYcpn", numYYCpn)
			t:SetValue(row_upd, "shareprc", tonumber(shareproc))
		
		end	
	end
end

function digits(n)
	local i, ret = -1
	return function()
	i, ret = i + 1, n % 10
	if n > 0 then
	n = math.floor(n / 10)
	return i, ret
	end
	end
end

level = false
function getname(pos, dig)
	level = level or pos % 3 == 0
	if(dig == 0) then return "" end
	local name = (pos % 3 == 1 and iwords[dig] or words[dig]) .. (pos % 3 == 2 and "hundred " or "")
	if(level) then name, level = name .. levels[math.floor(pos / 3)], false end
	return name
end

function numberToWord(number)
	if(number == 0) then return "zero" end
	vword = ""
	for i, v in digits(number) do
	vword = getname(i, v) .. vword
	end

	for i, v in ipairs(words) do
	vword = vword:gsub("ty " .. v, "ty-" .. v)
	vword = vword:gsub("ten " .. v, twords[i])
	end
	return vword
end

function _Time(t)
	hour = t.hour
	minute = t.min
	hour = hour % 12
	if(hour == 0) then 
	hour, nextHourWord = 12, "one "
	else
	nextHourWord = numberToWord(hour+1)
	end
	hourWord = numberToWord(hour)
	if(minute == 0 ) then 
	return hourWord .. "o'clock"
	elseif(minute == 30) then
	return "half past " .. hourWord
	elseif(minute == 15) then
	return "a quarter past " .. hourWord 
	elseif(minute == 45) then
	return "a quarter to " .. nextHourWord 
	else
	if(minute < 30) then
	return numberToWord(minute) .. "past " .. hourWord
	else
	return numberToWord(60-minute) .. "to " .. nextHourWord
	end
	end
end

function _Seconds(s)
	return numberToWord(s)
end

function NiceTime(t)
	return _Time(t) .."and ".. _Seconds(t.sec) .. "second"
end
