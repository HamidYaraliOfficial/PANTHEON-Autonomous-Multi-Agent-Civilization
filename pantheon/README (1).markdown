# PANTHEON — Autonomous Multi-Agent Civilization

*An Erlang/OTP + Elixir + Lua foundation for simulating a world where agents live, work, trade, form families, and let economy, culture and language emerge from their interactions — with a Windows‑11‑styled dashboard in English, Persian (فارسی) and Chinese (中文).*

This single document is written three times, once per language. Jump to the section you need:

- [🇬🇧 English](#english)
- [🇮🇷 فارسی](#فارسی)
- [🇨🇳 中文](#中文)

---
---

## English

### Overview

PANTHEON is a multi-language simulation platform built around a simple division of labor:

- **Erlang/OTP** (`apps/erlang_engine`) is the raw actor engine: one supervised OTP process per agent, spatial partitioning by region, an ETS-backed id registry, a pub/sub event bus, and a deterministic, seed-derived random number generator so the same seed always reproduces the same history.
- **Elixir** (`apps/pantheon_core`, `apps/pantheon_web`) is the control plane: world generation, the economic/cultural/linguistic subsystems, persistence, the Lua bridge, and a REST + WebSocket API.
- **Lua** (`apps/pantheon_core/priv/lua`), executed through the pure-Erlang, sandboxed [Luerl](https://github.com/rvirding/luerl) VM (no native code, no filesystem/network access), defines agent archetypes and decision policies — so behaviour can be authored and hot-reloaded without recompiling the engine.

A static, dependency-free dashboard (`frontend/`) talks to the backend over REST and a live WebSocket feed, with five selectable themes and full English/Persian/Chinese localization, including automatic right-to-left layout for Persian.

### Key Features

- **Actor-based agent simulation** — needs, goals, personality, bounded memory, relationships and an `active / sleeping / dormant` activity model per agent, each its own supervised OTP process.
- **Pluggable Lua behaviour policies** — farmer / trader / artisan archetypes ship as editable `.lua` files; a broken or malicious script can never crash the engine (every call is time-boxed and falls back to a built-in heuristic).
- **Procedural World Generation Engine** — deterministic biomes, climate, fertility, water access and starting resources per region, derived purely from the world seed.
- **Emergent multi-market economy** — per-region supply/demand pricing, resource regeneration, and cross-region trade transfers.
- **Culture & Language Evolution Engines** — norms, rituals, symbols and stories with tracked origins; synthetic per-civilization languages with word coinage, name generation, and generational sound-change drift.
- **Narrative event log** — every meaningful occurrence is published on a global event bus, recorded to a durable, replayable NDJSON log, and streamed live to the dashboard.
- **Deterministic, seed-based reproducibility** — the same world seed and engine version reproduce the same history.
- **Fault-tolerant supervision tree** — a crash in one agent, or an entire region, is isolated and self-heals without affecting the rest of the world.
- **Configurable server operating hours** — an admin-editable weekly schedule (per day, multiple time windows, UTC offset) drives a live "open now / opens in Xh Ym" status widget on the dashboard.
- **Five UI themes** — Windows 11 (default), Light, Dark, Red accent and Blue accent — plus English, Persian and Chinese localization with correct RTL/LTR handling.

### Architecture

```
apps/
  erlang_engine/   Raw actor core (pure Erlang/OTP)
    src/
      erlang_engine_app.erl      application entry point
      erlang_engine_sup.erl      root supervisor
      world_registry.erl         ETS-backed id -> pid registry
      event_bus.erl              topic pub/sub
      det_rng.erl                deterministic seeded RNG
      region_partition_sup.erl   one supervisor per world region
      region_agent_sup.erl       one supervisor per agent within a region
      agent_actor.erl            the agent process itself

  pantheon_core/   Elixir control plane
    lib/pantheon_core/
      world.ex            World Builder Wizard, calendar, tick loop
      world_gen.ex         procedural geography/climate/resources
      economy.ex           multi-market supply/demand pricing
      culture.ex           norms/rituals/symbols/stories + drift/contact
      language.ex          synthetic languages, word coinage, drift
      history.ex           event log / World Chronicle backbone
      lua_engine.ex         sandboxed Lua execution via Luerl
      agent.ex              Elixir façade over agent_actor
      operating_hours.ex    configurable open-hours schedule + status
      snapshot.ex           event log + full-world JSON snapshots
      scheduler.ex          wall-clock tick driver
    priv/lua/
      archetypes/           farmer.lua, trader.lua, artisan.lua
      rules/                example culture/economy rule templates

  pantheon_web/    REST API + WebSocket + static dashboard host
    lib/pantheon_web/
      router.ex            REST endpoints + static file serving
      socket_handler.ex     live event/tick streaming over WebSocket
      application.ex        Cowboy listener wiring

frontend/          Static dashboard (no build step)
  index.html, css/theme.css, css/layout.css
  js/i18n.js, js/operating_hours.js, js/app.js
  locales/en.json, fa.json, zh.json

scripts/seed_world.exs   headless world bootstrap
data/snapshots/          durable event log + world snapshots (generated)
```

### Requirements

- **Erlang/OTP 26** or later
- **Elixir 1.15** or later (bundled with a compatible OTP, or installed against the OTP above)
- A modern web browser (the dashboard is plain HTML/CSS/JS — no Node.js or build step required)

Installing Erlang and Elixir:

```bash
# Debian/Ubuntu
sudo apt-get update && sudo apt-get install -y erlang elixir

# Fedora
sudo dnf install -y erlang elixir

# macOS (Homebrew)
brew install erlang elixir

# Windows (Chocolatey, run in an elevated PowerShell)
choco install erlang elixir

# Any OS, via asdf (recommended if you juggle multiple versions)
asdf plugin add erlang
asdf plugin add elixir
asdf install erlang 26.2.5
asdf install elixir 1.17.3-otp-26
asdf local erlang 26.2.5
asdf local elixir 1.17.3-otp-26
```

### Installation & Running

Open a terminal in the project's root folder (the folder containing `mix.exs`) and run:

```bash
# 1. Install the Hex package manager and Rebar (Erlang's build tool),
#    needed once per machine to fetch dependencies such as Luerl.
mix local.hex --force
mix local.rebar --force

# 2. Fetch dependencies
mix deps.get

# 3. Compile the whole umbrella
mix compile

# 4. Run the test suite (optional, but recommended)
mix test

# 5. Start PANTHEON — this boots the actor engine, the control plane,
#    and the web dashboard on http://localhost:4000
mix run --no-halt
```

Then open **http://localhost:4000** in your browser:

1. Go to **World Overview** and use the **World Builder Wizard** to set a seed, world name, number of regions/civilizations, agents per region, and resource abundance, then click **Generate world**.
2. Click **Start clock** to begin the simulation. Use the speed slider to fast-forward.
3. Explore **Regions**, **Civilizations**, **Agent Inspector**, **Timeline** (live event feed), **Economy** and **Culture & Language** from the sidebar.

For a headless run with no dashboard (useful for long simulations on a server), use:

```bash
mix run scripts/seed_world.exs
```

### Configuring Server Operating Hours

The **Settings** page lets you type in exactly when the live world should be open to visitors:

1. Set a **timezone offset from UTC**, in minutes.
2. For each day of the week, add one or more **open/close time windows** (24-hour `HH:MM` format), or leave a day empty to mark it fully closed.
3. Click **Save schedule**.

The dashboard immediately shows a live pill — **Open now** or **Closed now** — together with a running countdown to the next change (**Closes in 2h 14m** / **Opens in 5h 03m**), computed entirely from the schedule you entered. This is independent of whether the simulation clock itself is running.

### Running Tests

```bash
mix test
```

Covers deterministic RNG reproducibility, procedural world generation, language coinage/drift, and the REST API surface. Extend these freely — every module was written to be unit-testable in isolation.

### Scope & Roadmap

This repository is a genuine, working foundation for the full PANTHEON vision — actor-based agents with needs/goals/personality/memory, a pluggable Lua behaviour layer, emergent economy, culture and language, deterministic replay, fault-tolerant supervision, and a themed, localized dashboard all function today, end to end.

The original design brief also describes a far larger set of engines (full diplomacy and conflict simulation, government and institution evolution, a distributed multi-node cluster running millions of agents, a 3D planet viewer, a counterfactual branching lab, and dozens more). Those are genuinely multi-year engineering efforts; they are **not** included here as working code, but the architecture (supervision tree, event bus, Lua policy layer, snapshot/event-sourcing persistence) is deliberately shaped so each of them can be added as its own module without restructuring what already exists. Treat this as the load-bearing skeleton, not the finished cathedral.

### License

Released under the [MIT License](./LICENSE) — see that file for the full text.

---
---

## فارسی

### معرفی

PANTHEON یک بستر شبیه‌سازی چندزبانه است که بر پایه‌ی تقسیم‌کار ساده‌ای ساخته شده:

- **Erlang/OTP** (پوشه‌ی `apps/erlang_engine`) موتور خام Actor است: به ازای هر عامل یک پردازه‌ی نظارت‌شده‌ی OTP، افراز فضایی بر اساس منطقه، یک رجیستری شناسه مبتنی بر ETS، یک گذرگاه رویداد (event bus) و یک تولیدکننده‌ی عدد تصادفی قطعی و مبتنی بر seed که تضمین می‌کند یک seed یکسان همیشه همان تاریخ را بازتولید کند.
- **Elixir** (پوشه‌های `apps/pantheon_core` و `apps/pantheon_web`) لایه‌ی کنترل است: تولید جهان، زیرسیستم‌های اقتصادی/فرهنگی/زبانی، ماندگاری داده، پل ارتباطی به Lua، و یک API از نوع REST + WebSocket.
- **Lua** (پوشه‌ی `apps/pantheon_core/priv/lua`) که از طریق ماشین مجازی Sandbox‌شده و تماماً Erlang به‌نام [Luerl](https://github.com/rvirding/luerl) اجرا می‌شود (بدون کد Native، بدون دسترسی به فایل‌سیستم یا شبکه)، کهن‌الگوهای رفتاری و سیاست‌های تصمیم‌گیری عامل‌ها را تعریف می‌کند؛ یعنی رفتار عامل‌ها را می‌توان بدون کامپایل مجدد موتور، نوشت و به‌روزرسانی کرد.

یک داشبورد استاتیک و بدون وابستگی (پوشه‌ی `frontend/`) از طریق REST و یک جریان زنده‌ی WebSocket با Backend صحبت می‌کند و دارای پنج تم قابل انتخاب و بومی‌سازی کامل به سه زبان انگلیسی، فارسی و چینی است؛ از جمله چیدمان خودکار راست‌به‌چپ برای فارسی.

### ویژگی‌های کلیدی

- **شبیه‌سازی عامل‌محور مبتنی بر Actor** — نیازها، اهداف، شخصیت، حافظه‌ی محدود، روابط اجتماعی و مدل فعالیتی `active / sleeping / dormant` برای هر عامل، که هرکدام یک پردازه‌ی مستقل و نظارت‌شده‌ی OTP هستند.
- **سیاست‌های رفتاری قابل‌تعویض با Lua** — کهن‌الگوهای کشاورز، بازرگان و صنعتگر به‌صورت فایل‌های ویرایش‌پذیر `.lua` ارائه شده‌اند؛ یک اسکریپت خراب یا مخرب هرگز نمی‌تواند موتور را از کار بیندازد (هر فراخوانی زمان‌بندی‌شده است و در صورت خطا به یک قاعده‌ی پیش‌فرض داخلی بازمی‌گردد).
- **موتور تولید رویه‌ای جهان** — زیست‌بوم، اقلیم، حاصلخیزی، دسترسی به آب و منابع اولیه‌ی هر منطقه، به‌صورت کاملاً قطعی و برگرفته از seed جهان.
- **اقتصاد چندبازاره‌ی نوظهور** — قیمت‌گذاری عرضه/تقاضا به تفکیک هر منطقه، بازتولید منابع، و انتقال کالا بین مناطق.
- **موتورهای تحول فرهنگ و زبان** — هنجارها، آیین‌ها، نمادها و داستان‌ها با ثبت منشأ هر عنصر؛ زبان‌های مصنوعی اختصاصی هر تمدن با واژه‌سازی، نام‌گذاری، و تحول آوایی بین نسلی.
- **گزارش رویدادهای روایی** — هر رویداد مهم روی یک گذرگاه رویداد سراسری منتشر، در یک لاگ ماندگار و قابل بازپخش (NDJSON) ثبت، و به‌صورت زنده به داشبورد ارسال می‌شود.
- **بازتولیدپذیری قطعی مبتنی بر Seed** — seed جهان و نسخه‌ی موتور یکسان، همان تاریخ را بازتولید می‌کنند.
- **درخت نظارت مقاوم در برابر خطا** — خرابی یک عامل یا حتی یک منطقه‌ی کامل، ایزوله شده و بدون تأثیر بر بقیه‌ی جهان خود-ترمیم می‌شود.
- **ساعات کاری قابل‌تنظیم سرور** — یک برنامه‌ی هفتگی قابل ویرایش توسط مدیر (به تفکیک روز، با چند بازه‌ی زمانی، و آفست UTC) که یک ابزارک وضعیت زنده‌ی «هم‌اکنون باز / تا باز شدن Xساعت Yدقیقه» را در داشبورد نمایش می‌دهد.
- **پنج تم رابط کاربری** — ویندوز ۱۱ (پیش‌فرض)، روشن، تیره، تم قرمز و تم آبی — به‌همراه بومی‌سازی انگلیسی، فارسی و چینی با پشتیبانی صحیح از راست‌به‌چپ/چپ‌به‌راست.

### معماری

ساختار پوشه‌ها دقیقاً همان چیزی است که در بخش انگلیسی همین سند نمایش داده شده (بخش «Architecture»)؛ از آنجا که مسیرهای فایل و نام ماژول‌ها به زبان انگلیسی نوشته می‌شوند، برای مرجع کامل به آن بخش مراجعه کنید.

### پیش‌نیازها

- **Erlang/OTP نسخه‌ی ۲۶** یا جدیدتر
- **Elixir نسخه‌ی ۱.۱۵** یا جدیدتر
- یک مرورگر وب مدرن (داشبورد صرفاً HTML/CSS/JS ساده است و به Node.js یا مرحله‌ی Build نیازی ندارد)

نصب Erlang و Elixir:

```bash
# Debian/Ubuntu
sudo apt-get update && sudo apt-get install -y erlang elixir

# Fedora
sudo dnf install -y erlang elixir

# macOS (Homebrew)
brew install erlang elixir

# ویندوز (Chocolatey — در یک PowerShell با دسترسی مدیر اجرا شود)
choco install erlang elixir

# در هر سیستم‌عاملی، از طریق asdf (در صورت نیاز به چند نسخه‌ی هم‌زمان توصیه می‌شود)
asdf plugin add erlang
asdf plugin add elixir
asdf install erlang 26.2.5
asdf install elixir 1.17.3-otp-26
asdf local erlang 26.2.5
asdf local elixir 1.17.3-otp-26
```

### نصب و اجرا

یک ترمینال در پوشه‌ی ریشه‌ی پروژه (پوشه‌ای که فایل `mix.exs` در آن قرار دارد) باز کنید و دستورهای زیر را اجرا کنید:

```bash
# ۱. نصب مدیر بسته‌ی Hex و Rebar (ابزار ساخت Erlang) —
#    یک‌بار روی هر سیستم لازم است تا وابستگی‌هایی مثل Luerl دریافت شوند.
mix local.hex --force
mix local.rebar --force

# ۲. دریافت وابستگی‌ها
mix deps.get

# ۳. کامپایل کل Umbrella
mix compile

# ۴. اجرای مجموعه تست‌ها (اختیاری، اما توصیه می‌شود)
mix test

# ۵. اجرای PANTHEON — این دستور موتور Actor، لایه‌ی کنترل و داشبورد وب
#    را روی آدرس http://localhost:4000 بالا می‌آورد
mix run --no-halt
```

سپس آدرس **http://localhost:4000** را در مرورگر باز کنید:

۱. به بخش **نمای کلی جهان** بروید و با استفاده از **جادوگر ساخت جهان**، seed، نام جهان، تعداد مناطق/تمدن‌ها، تعداد عامل در هر منطقه و فراوانی منابع را تنظیم کرده و روی **ساخت جهان** کلیک کنید.
۲. برای شروع شبیه‌سازی روی **شروع ساعت شبیه‌سازی** کلیک کنید. از اسلایدر سرعت برای تسریع زمان استفاده کنید.
۳. بخش‌های **مناطق**، **تمدن‌ها**، **بازرس عامل‌ها**، **خط زمانی** (جریان زنده‌ی رویدادها)، **اقتصاد** و **فرهنگ و زبان** را از نوار کناری بررسی کنید.

برای اجرای بدون رابط گرافیکی (Headless — مناسب برای شبیه‌سازی‌های طولانی روی سرور):

```bash
mix run scripts/seed_world.exs
```

### تنظیم ساعات کاری سرور

صفحه‌ی **تنظیمات** به شما اجازه می‌دهد دقیقاً مشخص کنید جهان زنده چه زمان‌هایی برای بازدیدکنندگان باز باشد:

۱. یک **آفست منطقه‌ی زمانی نسبت به UTC** بر حسب دقیقه تنظیم کنید.
۲. برای هر روز هفته، یک یا چند **بازه‌ی زمانی باز/بسته شدن** (با فرمت ۲۴ ساعته‌ی `HH:MM`) اضافه کنید، یا روزی را بدون هیچ بازه‌ای رها کنید تا آن روز کاملاً تعطیل باشد.
۳. روی **ذخیره برنامه** کلیک کنید.

داشبورد بلافاصله یک نشانگر زنده — **هم‌اکنون باز است** یا **هم‌اکنون بسته است** — به‌همراه شمارش معکوس تا تغییر بعدی (مثلاً «زمان تا بسته شدن: ۲ ساعت ۱۴ دقیقه» یا «زمان تا باز شدن: ۵ ساعت ۳ دقیقه») نمایش می‌دهد که تماماً از روی برنامه‌ای که شما وارد کرده‌اید محاسبه می‌شود؛ این ویژگی کاملاً مستقل از روشن یا خاموش بودن ساعت شبیه‌سازی است.

### اجرای تست‌ها

```bash
mix test
```

این مجموعه، بازتولیدپذیری قطعی RNG، تولید رویه‌ای جهان، واژه‌سازی و تحول زبان، و سطح API را پوشش می‌دهد. افزودن تست‌های بیشتر کاملاً آزاد است؛ هر ماژول طوری نوشته شده که به‌صورت مستقل قابل تست باشد.

### دامنه‌ی پروژه و نقشه‌ی راه

این مخزن یک پایه‌ی واقعی و کاملاً کارکردی برای چشم‌انداز کامل PANTHEON است: عامل‌های مبتنی بر Actor با نیاز/هدف/شخصیت/حافظه، یک لایه‌ی رفتاری قابل‌تعویض با Lua، اقتصاد و فرهنگ و زبان نوظهور، بازپخش قطعی، درخت نظارت مقاوم در برابر خطا، و یک داشبورد تم‌دار و چندزبانه — همگی همین امروز و به‌صورت سرتاسری کار می‌کنند.

سند طراحی اصلی همچنین مجموعه‌ی بسیار بزرگ‌تری از موتورها را توصیف می‌کند (شبیه‌سازی کامل دیپلماسی و درگیری، تحول حکومت و نهادها، خوشه‌ی توزیع‌شده‌ی چندگره‌ای برای میلیون‌ها عامل، نمایشگر سیاره‌ی سه‌بعدی، آزمایشگاه شاخه‌های فرضی-متضاد و ده‌ها مورد دیگر). این‌ها واقعاً پروژه‌های مهندسی چندساله هستند و در این مخزن به‌صورت کد کارکردی **گنجانده نشده‌اند**؛ اما معماری (درخت نظارت، گذرگاه رویداد، لایه‌ی سیاست Lua، ماندگاری مبتنی بر Snapshot/Event-Sourcing) عمداً طوری طراحی شده که هرکدام از آن‌ها بتواند به‌صورت یک ماژول مستقل و بدون بازسازی آنچه از قبل وجود دارد اضافه شود. این مخزن را اسکلت باربر پروژه در نظر بگیرید، نه کلیسای جامع نهایی.

### مجوز

منتشر شده تحت [مجوز MIT](./LICENSE) — برای متن کامل به همان فایل مراجعه کنید.

---
---

## 中文

### 概述

PANTHEON 是一个基于清晰分工构建的多语言仿真平台:

- **Erlang/OTP**(位于 `apps/erlang_engine`)是原始的 Actor 引擎:每个智能体对应一个受监督的 OTP 进程,按区域进行空间分区,基于 ETS 的 ID 注册表,一个发布/订阅事件总线,以及一个基于种子的确定性随机数生成器——相同的种子总能重现相同的历史。
- **Elixir**(位于 `apps/pantheon_core` 与 `apps/pantheon_web`)是控制层:世界生成、经济/文化/语言子系统、持久化、Lua 桥接层,以及 REST + WebSocket API。
- **Lua**(位于 `apps/pantheon_core/priv/lua`)通过纯 Erlang 实现的沙盒虚拟机 [Luerl](https://github.com/rvirding/luerl) 执行(无原生代码,无文件系统或网络访问),用于定义智能体的原型与决策策略——因此行为脚本可以编写和热更新,无需重新编译引擎。

一个无需构建步骤的静态仪表盘(`frontend/`)通过 REST 与实时 WebSocket 与后端通信,提供五种可选主题,并完整支持英文、波斯语、中文本地化,包括波斯语所需的自动从右到左(RTL)布局。

### 核心特性

- **基于 Actor 的智能体仿真** —— 每个智能体拥有需求、目标、性格、有限记忆、社交关系,以及 `active / sleeping / dormant`(活跃/休眠/休止)活动状态模型,且各自是独立的、受监督的 OTP 进程。
- **可插拔的 Lua 行为策略** —— 农民、商人、工匠等原型以可编辑的 `.lua` 文件提供;损坏或恶意脚本永远不会使引擎崩溃(每次调用都有超时限制,失败时回退到内置的启发式决策)。
- **程序化世界生成引擎** —— 每个区域的生物群系、气候、肥沃度、水资源可达性与初始资源,均完全由世界种子确定性推导而来。
- **涌现式多市场经济** —— 按区域独立的供需定价、资源再生,以及跨区域贸易转移。
- **文化与语言演化引擎** —— 带有可追溯来源的规范、仪式、符号与故事;每个文明拥有独立的合成语言,支持词汇创造、命名生成以及跨代语音演变(音变漂移)。
- **叙事事件日志** —— 每一个重要事件都会发布到全局事件总线,记录到可持久化、可重放的 NDJSON 日志中,并实时推送到仪表盘。
- **基于种子的确定性可复现性** —— 相同的世界种子与引擎版本,总能重现相同的历史。
- **容错的监督树** —— 单个智能体乃至整个区域的崩溃都会被隔离并自我修复,不会影响世界的其余部分。
- **可配置的服务器开放时间** —— 管理员可编辑的每周时间表(按天设置多个时间段,并支持 UTC 偏移),驱动仪表盘上实时的"当前开放/还有 X 小时 Y 分钟开放"状态组件。
- **五种界面主题** —— Windows 11(默认)、浅色、深色、红色主题与蓝色主题——并支持英文、波斯语、中文本地化,正确处理 RTL/LTR 布局方向。

### 架构

目录结构与本文档英文部分("Architecture"小节)展示的完全一致;由于文件路径与模块名均以英文书写,完整参考请查阅该小节。

### 环境要求

- **Erlang/OTP 26** 或更高版本
- **Elixir 1.15** 或更高版本
- 一款现代网页浏览器(仪表盘只是纯 HTML/CSS/JS,无需 Node.js 或任何构建步骤)

安装 Erlang 与 Elixir:

```bash
# Debian/Ubuntu
sudo apt-get update && sudo apt-get install -y erlang elixir

# Fedora
sudo dnf install -y erlang elixir

# macOS(Homebrew)
brew install erlang elixir

# Windows(Chocolatey,在具有管理员权限的 PowerShell 中运行)
choco install erlang elixir

# 任意操作系统,通过 asdf 安装(如需管理多个版本,推荐使用)
asdf plugin add erlang
asdf plugin add elixir
asdf install erlang 26.2.5
asdf install elixir 1.17.3-otp-26
asdf local erlang 26.2.5
asdf local elixir 1.17.3-otp-26
```

### 安装与运行

在项目根目录(包含 `mix.exs` 文件的目录)打开终端,依次执行:

```bash
# 1. 安装 Hex 包管理器与 Rebar(Erlang 的构建工具)——
#    每台机器只需执行一次,用于获取诸如 Luerl 之类的依赖。
mix local.hex --force
mix local.rebar --force

# 2. 获取依赖
mix deps.get

# 3. 编译整个 umbrella 项目
mix compile

# 4. 运行测试套件(可选,但推荐执行)
mix test

# 5. 启动 PANTHEON —— 该命令会同时启动 Actor 引擎、控制层
#    以及监听在 http://localhost:4000 的网页仪表盘
mix run --no-halt
```

然后在浏览器中打开 **http://localhost:4000**:

1. 进入**世界概览**页面,使用**世界构建向导**设置种子、世界名称、区域/文明数量、每个区域的智能体数量以及资源丰度,然后点击**生成世界**。
2. 点击**启动时钟**开始仿真。使用速度滑块可以加快模拟速度。
3. 通过侧边栏浏览**区域**、**文明**、**智能体检视器**、**时间线**(实时事件流)、**经济**以及**文化与语言**等页面。

如需无界面(Headless)运行(适合在服务器上进行长时间仿真):

```bash
mix run scripts/seed_world.exs
```

### 配置服务器开放时间

**设置**页面允许你精确指定实时世界何时对访问者开放:

1. 设置相对 UTC 的**时区偏移**(以分钟为单位)。
2. 为每周的每一天添加一个或多个**开放/关闭时间段**(采用24小时制 `HH:MM` 格式),若某天不设置任何时间段,则表示该天全天关闭。
3. 点击**保存时间表**。

仪表盘会立即显示一个实时状态标签——**当前开放**或**当前关闭**——并配有距下一次状态变化的倒计时(例如"距关闭还有:2小时14分"或"距开放还有:5小时3分"),该倒计时完全根据你输入的时间表计算得出,与仿真时钟本身是否在运行无关。

### 运行测试

```bash
mix test
```

测试覆盖确定性随机数生成的可复现性、程序化世界生成、语言的词汇创造与演变,以及 REST API 接口。你可以自由扩展这些测试——每个模块在设计时都考虑了可独立单元测试性。

### 项目范围与路线图

本仓库是 PANTHEON 完整愿景的一个真实、可运行的基础版本:基于 Actor 的智能体(具备需求/目标/性格/记忆)、可插拔的 Lua 行为层、涌现式的经济/文化/语言系统、确定性重放、容错监督树,以及一个带主题和多语言支持的仪表盘——这些功能如今都已端到端地实际运行。

最初的设计构想还描述了规模远大得多的一系列引擎(完整的外交与冲突仿真、政府与制度演化、可运行数百万智能体的分布式多节点集群、三维星球查看器、反事实分支实验室等数十项功能)。这些确实是需要数年工程投入的项目;它们**并未**作为可运行代码包含在本仓库中,但整体架构(监督树、事件总线、Lua 策略层、基于快照/事件溯源的持久化)在设计时特意考虑到了可扩展性,使上述每一项都能作为独立模块添加,而无需重构现有代码。请将本仓库视为承重的骨架,而非最终完工的宏伟大教堂。

### 许可证

基于 [MIT 许可证](./LICENSE) 发布——完整文本请参阅该文件。
