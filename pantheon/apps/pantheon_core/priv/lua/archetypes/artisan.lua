-- PANTHEON Lua archetype: Artisan
-- Balances craft/status ambitions against survival and belonging needs;
-- occasionally produces a cultural artifact (feeds the Culture Engine).

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

  if worst_val < 0.3 then
    return { type = "satisfy_need", need = worst_key }
  end

  if (needs.status or 0.4) < 0.5 and (personality.ambition or 0.5) > 0.4 then
    return { type = "craft_artifact", need = "status" }
  end

  if (needs.belonging or 0.5) < 0.5 then
    return { type = "join_gathering", need = "belonging" }
  end

  return { type = "satisfy_need", need = worst_key or "status" }
end
