--this is probably all jank idk
memory = {}

MEMORY_INCREMENT = .25

--maybe i should change "offset" to "index"
function memory.write(offset, data, step, mirror)
    if type(data) != "number" and type(data) != "table" then
        return(offset) --return same offset to use since nothing is written
    end

    step = step or 1 --non-int step will be fine when utils.CreateScrollVelocity() accepts floats for StartTime
    mirror = mirror or false --setting mirror to true causes effect of sv to be (mostly) negated by an equal and opposite sv and then a 1x sv is placed

    if type(data) == "number" then
        if mirror then
            local svs = {}
            table.insert(svs, utils.CreateScrollVelocity(offset, data))
            table.insert(svs, utils.CreateScrollVelocity(offset + MEMORY_INCREMENT, -data))
            table.insert(svs, utils.CreateScrollVelocity(offset + 2 * MEMORY_INCREMENT, 1))
            actions.PlaceScrollVelocityBatch(svs)
        else
            actions.PlaceScrollVelocity(utils.CreateScrollVelocity(offset, data))
        end
        return(offset + step) --one sv placed, so increment offset by 1 step
    else --data is a table
        local svs = {}
        for i, value in pairs(data) do
            table.insert(svs, utils.CreateScrollVelocity(offset + step * (i-1), value))
            if mirror then
                table.insert(svs, utils.CreateScrollVelocity(offset + step * (i-1) + MEMORY_INCREMENT, -value))
                table.insert(svs, utils.CreateScrollVelocity(offset + step * (i-1) + 2 * MEMORY_INCREMENT, 1))
            end
        end
        actions.PlaceScrollVelocityBatch(svs)
        return(offset + #data * step) --increment offset by number of elements in data times step
    end
end

function memory.search(start, stop)
    local svs = map.ScrollVelocities --I'm assuming this returns the svs in order so I'm not sorting them
    local selection = {}
    for _, sv in pairs(svs) do
        if (start <= sv.StartTime) and (sv.StartTime <= stop) then
            table.insert(selection, sv)
        elseif sv.StartTime > stop then --since they're in order, I should be able to return once StartTime exceeds stop
            break
        end
    end
    return(selection) --returns table of svs
end

function memory.read(start, stop, step)
    if not start then
        return(false)
    end

    step = step or 1 --step indicated which svs are for data and which are for mirroring
    stop = stop or start --stop defaults to start, so without a stop provided, function returns one item
    local selection = {}
    local x
    for _, sv in pairs(memory.search(start, stop)) do
        if not x then
            x = sv.StartTime - 1 --assume first sv is actual data
        end
        if (sv.StartTime - x) % step == 0 then --by default, anything without integer starttime is not included
            selection[sv.StartTime - x] = sv.Multiplier
        end
    end
    if #selection == 1 then --if table of only one element
        return(selection[1]) --return element
    else --otherwise
        return(selection) --return table of elements
    end
end

function memory.delete(start, stop, step)
    if not start then
        return(false)
    end

    step = step or 1
    stop = stop or start + 2 * MEMORY_INCREMENT

    local svs = memory.search(start, stop)
    local selection = {}
    local x

    for _, sv in pairs(svs) do
        if not x then
            x = sv.StartTime - 1
        end
        if (sv.StartTime - x) % step == 0 then
            selection[sv.StartTime - x] = sv.Multiplier
        end
    end

    actions.RemoveScrollVelocityBatch(svs)
    if #selection == 1 then --if table of only one element
        return(selection[1]) --return element
    else --otherwise
        return(selection) --return table of elements
    end
end

function memory.generateCorrectionSVs(limit, offset) --because there's going to be a 1293252348328x SV that fucks the game up
    local svs = map.ScrollVelocities --if these don't come in order i'm going to hurt someone

    local totaldisplacement = 0

    for i, sv in pairs(svs) do
        if (sv.StartTime < limit) and not (sv.StartTime == offset or sv.StartTime == offset + 1) then
            length = svs[i+1].StartTime - sv.StartTime
            displacement = length * (sv.Multiplier - 1) --displacement in ms as a distance
            totaldisplacement = totaldisplacement + displacement --total displacement in ms as a distance
        else
            break
        end
    end

    corrections = {}
    table.insert(corrections, utils.CreateScrollVelocity(offset, -totaldisplacement + 1)) --i think this is correct?
    table.insert(corrections, utils.CreateScrollVelocity(offset + 1, 1))

    return(corrections)
end

function memory.correctDisplacement(limit, offset) --will not work if there's an ultra large number at the end
    local limit = limit or 0 --where the memory ends
    local offset = offset or -10000002 --SVs will return with StartTime = offset and offset + 10000

    local currentsvs = {}
    table.insert(currentsvs, getScrollVelocityAtExactly(offset))
    table.insert(currentsvs, getScrollVelocityAtExactly(offset + 1))
    actions.RemoveScrollVelocityBatch(currentsvs)

    actions.PlaceScrollVelocityBatch(memory.generateCorrectionSVs(limit, offset))
end

function getScrollVelocityAtExactly(time)
    local currentsv = map.GetScrollVelocityAt(time)
    if currentsv.StartTime == time then
        return(currentsv)
    end
end

function tableToString(table)
    local result = ""
    for i,value in pairs(table) do
        result = result .. "[" .. i .. "]: " .. value .. ", "
    end
    result:sub(1,-3)

    return(result)
end

function draw()
    imgui.Begin("Memory")

    --now you may be wondering why these "constants" are storing their values with state.SetValue(), and that's a good question
    local MEMORY_OFFSET = state.GetValue("MEMORY_OFFSET") or -2000000 --start writing at -2 million ms
    local MEMORY_LIMIT = state.GetValue("MEMORY_LIMIT") or -1000000 --all memory stuff must be at an offset less than -1 million
    local CORRECTION_OFFSET = state.GetValue("CORRECTION_OFFSET") or -10000000 --where the SV that corrects visual precision errors will be placed
    local offset = state.GetValue("offset") or MEMORY_OFFSET

    --write
    local number = state.GetValue("number") or 0
    local values = state.GetValue("values") or {}
    local valuesstring = state.GetValue("valuesstring") or ""

    --read
    local start = state.GetValue("start") or -2000000
    local stop = state.GetValue("stop") or -1000001
    local result = state.GetValue("result") or {}
    local resultstring = state.GetValue("resultstring") or ""

    --debug
    debug = state.GetValue("debug") or "hi"

    state.IsWindowHovered = imgui.IsWindowHovered()

    --write
    _, number = imgui.InputFloat("Number", number)
    _, offset = imgui.InputFloat("Offset", offset, 1)

    if imgui.Button("Add Number to Values") then
        table.insert(values, number)

        valuesstring = tableToString(values)
    end

    if imgui.Button("Store Number") then
        offset = memory.write(offset, number)
    end

    if imgui.Button("Store Values") then
        offset = memory.write(offset, values)
        values = {}
        valuesstring = ""
    end

    imgui.TextWrapped("Offset: " .. offset)
    imgui.TextWrapped("Values: " .. valuesstring)

    imgui.Separator()

    --read
    _, start = imgui.InputFloat("Start", start)
    _, stop = imgui.InputFloat("Stop", stop)

    if imgui.Button("Retrieve Data") then
        result = memory.read(start, stop)

        resultstring = tableToString(result)
    end

    if imgui.Button("Delete Data") then
        memory.delete(start, stop)

        result = {}
        resultstring = ""
    end

    imgui.TextWrapped("Result: " .. resultstring)

    imgui.Separator()

    --correction
    if imgui.Button("Correct Displacement") then
        memory.correctDisplacement(MEMORY_LIMIT)
    end

    imgui.Separator()

    --debug
    imgui.TextWrapped("Debug: " .. debug)

    --"constants" or smtg idk
    state.SetValue("MEMORY_OFFSET", MEMORY_OFFSET)
    state.SetValue("MEMORY_LIMIT", MEMORY_LIMIT)
    state.SetValue("CORRECTION_OFFSET", CORRECTION_OFFSET)
    state.SetValue("offset", offset)

    --write
    state.SetValue("number", number)
    state.SetValue("values", values)
    state.SetValue("valuesstring", valuesstring)

    --read
    state.SetValue("start", start)
    state.SetValue("stop", stop)
    state.SetValue("result", result)
    state.SetValue("resultstring", resultstring)

    --debug
    state.SetValue("debug", debug)

    imgui.End()
end
