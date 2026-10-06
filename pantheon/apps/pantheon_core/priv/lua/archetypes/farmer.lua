-- PANTHEON Lua archetype: Farmer
-- Contract: define decide(agent) and return a plain table describing the
-- chosen action. `agent` is a read-only snapshot injected by the engine
-- (see PantheonCore.LuaEngine) — nothing you do here can reach the real
-- filesystem or network; Luerl exposes only the sandboxed Lua stdlib.

local function most_urgent_need(needs)
  local worst_key, worst_val = nil, 2.0
  for k, v in pairs(needs) do
    if v < worst_val then
      worst_key, worst_val = k, v
    end
  end
  return worst_key, worst_val
end

function decide(agent)
  local needs = agent.needs or {}
  local personality = agent.personality or {}
  local worst_key, worst_val = most_urgent_need(needs)

  -- Farmers strongly prioritise food/water/shelter over anything else;
  -- ambition and curiosity only matter once survival needs are healthy.
  if worst_val < 0.35 and (worst_key == "food" or worst_key == "water" or worst_key == "shelter") then
    return { type = "farm_or_gather", need = worst_key, urgency = worst_val }
  end

  if (needs.income or 0.5) < 0.4 then
    return { type = "sell_surplus", need = "income" }
  end

  if (personality.curiosity or 0.5) > 0.7 and (needs.safety or 1.0) > 0.6 then
    return { type = "explore_nearby", need = "curiosity" }
  end

  return { type = "satisfy_need", need = worst_key or "food" }
end
