-- PANTHEON Lua rule template: Culture Rule
-- Rule scripts implement on_event(ctx) instead of decide(agent). `ctx` is
-- whatever context table the caller passes to
-- PantheonCore.LuaEngine.run_hook/3 (for example, a civilization summary
-- plus the triggering event). Return a plain table describing what
-- should happen; the calling Elixir module (e.g. PantheonCore.Culture)
-- decides how to apply it — Lua never mutates world state directly.

function on_event(ctx)
  local civ = ctx.civilization or {}
  local event = ctx.event or {}

  if event.kind == "famine" then
    return { action = "add_norm", content = "store grain against lean years" }
  end

  if event.kind == "victory" then
    return { action = "add_ritual", content = "feast of " .. (event.label or "the harvest") }
  end

  return { action = "none" }
end
