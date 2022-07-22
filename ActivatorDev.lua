local filepath = _G.GetCurrentFilePath()
local localVersionPath = "lol\\Modules\\ActivatorDev"
if not filepath:find(localVersionPath) and io.exists(localVersionPath .. ".lua") then
    require(localVersionPath)
    return
end

module("SActivator", package.seeall, log.setup)
clean.module("SActivator", clean.seeall, log.setup)

local VERSION = "1.0.5"
local LAST_UPDATE = "22, July 2022"

----------------------------------------------------------------------------------------------

local SDK = _G.CoreEx

local DamageLib, CollisionLib, Menu, Prediction, TargetSelector, Orbwalker, Spell, TS =
    _G.Libs.DamageLib,
    _G.Libs.CollisionLib,
    _G.Libs.NewMenu,
    _G.Libs.Prediction,
    _G.Libs.TargetSelector,
    _G.Libs.Orbwalker,
    _G.Libs.Spell,
    _G.Libs.TargetSelector()

local ObjectManager, EventManager, Input, Game, Geometry, Renderer, Enums, Evade =
    SDK.ObjectManager,
    SDK.EventManager,
    SDK.Input,
    SDK.Game,
    SDK.Geometry,
    SDK.Renderer,
    SDK.Enums,
    SDK.EvadeAPI

local Events, SpellSlots, SpellStates, HitChance, BuffType, Vector =
    Enums.Events,
    Enums.SpellSlots,
    Enums.SpellStates,
    Enums.HitChance,
    Enums.BuffTypes,
    Geometry.Vector

local abs, huge, min, deg, sin, cos, acos, pi, floor, sqrt =
    _G.math.abs,
    _G.math.huge,
    _G.math.min,
    _G.math.deg,
    _G.math.sin,
    _G.math.cos,
    _G.math.acos,
    _G.math.pi,
    _G.math.floor,
    _G.math.sqrt

local clock = _G.os.clock
local myHero = Player
local myCharName = myHero.CharName
local ItemID = require("lol\\Modules\\Common\\ItemID")

--_G.CoreEx.Evade.IsDebugEnabled = true

----------------------------------------------------------------------------------------------

local Heroes = {}
local VisionTable = {}
local OnScreenCallback = {}
local BasePosition = myHero.TeamId == 200 and Vector(14302, 172, 14387) or Vector(415, 182, 415)
local ActivatorDisabled = false
local MenuIsLoading = true

local Items = {}
local Summoners = {}
local ItemUpdateInterval = 5
local ItemLastUpdate = 0

local CurrentTarget = nil
local TargetUpdateInterval = 0.5
local TargetLastUpdate = 0

local Buffs = {}
local PotionBuff = false

local DetectedTargetMissiles = {}
local DetectedParticles = {}
local DetectedTargetSpells = {}

local ShieldSpell = nil
local SmiteSpell = nil
local AutoJumpSpell = nil

local EnemyCount = 0
local EnemyIsNear = false
local EnemyIsNearAroundAlly = {}
local AllyCount = {
    [ItemID.ShurelyasBattlesong] = 0,
    [ItemID.LocketOftheIronSolari] = 0,
}

local CachedSmiteDamage = 450
local EnemyJunglers = {}

local ShouldWardJump = false
local WardJumpLastCastT = 0

local SlotToString = {
    [-1] = "Passive",
    [SpellSlots.Q] = "Q",
    [SpellSlots.W] = "W",
    [SpellSlots.E] = "E",
    [SpellSlots.R] = "R",
}

local ItemType = {
    ["Cleanse"] = 1,
    ["Defensive"] = 2,
    ["Offensive"] = 3,
    ["Consumable"] = 4,
    ["Instant"] = 5
}

local CastType = {
    ["Targeted"] = 1,
    ["Active"] = 2,
    ["Skillshot"] = 3,
}

local SummonerData = {
    ["SummonerBarrier"] = { CastType = CastType.Active, Name = "Barrier", CastRange = 0, Config = { AddOnlyCombo = true, AddIgnoreCombo = true }, },
    ["SummonerBoost"] = { CastType = CastType.Active, Name = "Cleanse", CastRange = 0, Config = { AddOnlyCombo = true, AddDebuffs = true, AddDelay = true }, },
    ["SummonerDot"] = { CastType = CastType.Active, Name = "Ignite", CastRange = 600, Config = {} },
    --["SummonerExhaust"] = { CastType = CastType.Targeted, Name = "Exhaust", CastRange = 650, Config = { AddOnlyCombo = true, AddEnemies = true }, },
    ["SummonerHeal"] = { CastType = CastType.Targeted, Name = "Heal", CastRange = 850, Config = { AddOnlyCombo = true, AddIgnoreCombo = true, AddAllies = true, AddOwnMaxHealth = true, AddAllyMaxHealth = true, DefaultHealthValue = 10 }, },
}

local ShieldData = {
    ["Ivern"] = { Slot = SpellSlots.E, CastType = CastType.Targeted, Name = "Triggerseed", Range = 750, Config = { AddOnlyCombo = true, AddIgnoreCombo = true, AddAllies = true, AddOwnMaxHealth = true, AddAllyMaxHealth = true, DefaultHealthValue = 20 }},
    ["Janna"] = { Slot = SpellSlots.E, CastType = CastType.Targeted, Name = "Eye of the Storm", Range = 800, Config = { AddOnlyCombo = true, AddIgnoreCombo = true, AddAllies = true, AddOwnMaxHealth = true, AddAllyMaxHealth = true, DefaultHealthValue = 20, AddOnAttack = true }},
    ["Karma"] = { Slot = SpellSlots.E, CastType = CastType.Targeted, Name = "Inspire", Range = 800, Config = { AddOnlyCombo = true, AddIgnoreCombo = true, AddAllies = true, AddOwnMaxHealth = true, AddAllyMaxHealth = true, DefaultHealthValue = 20 } },
    ["LeeSin"] = { Slot = SpellSlots.W, CastType = CastType.Targeted, Name = "Safeguard", Range = 700, Config = { AddOnlyCombo = true, AddIgnoreCombo = true, AddAllies = true, AddOwnMaxHealth = true, AddAllyMaxHealth = true, DefaultHealthValue = 20 } },
    ["Lulu"] = { Slot = SpellSlots.E, CastType = CastType.Targeted, Name = "Help, Pix!", Range = 650, Config = { AddOnlyCombo = true, AddIgnoreCombo = true, AddAllies = true, AddOwnMaxHealth = true, AddAllyMaxHealth = true, DefaultHealthValue = 20 } },
    ["Lux"] = { Slot = SpellSlots.W, CastType = CastType.Skillshot, Name = "Prismatic Barrier", Range = 1175, Config = { AddOnlyCombo = true, AddIgnoreCombo = true, AddAllies = true, AddOwnMaxHealth = true, AddAllyMaxHealth = true, DefaultHealthValue = 20 }, Delay = 0.25, Speed = 2400, Width = 220 },
    ["Orianna"] = { Slot = SpellSlots.E, CastType = CastType.Targeted, Name = "Command Protect", Range = 1120, Config = { AddOnlyCombo = true, AddIgnoreCombo = true, AddAllies = true, AddOwnMaxHealth = true, AddAllyMaxHealth = true, DefaultHealthValue = 20 } },
    ["Seraphine"] = { Slot = SpellSlots.W, CastType = CastType.Active, Name = "Surround Sound", Range = 800, Config = { AddOnlyCombo = true, AddIgnoreCombo = true, AddAllies = true, AddOwnMaxHealth = true, AddAllyMaxHealth = true, DefaultHealthValue = 20 } },
    ["Sona"] = { Slot = SpellSlots.W, CastType = CastType.Active, Name = "Aria of Perseverance", Range = 1000, Config = { AddOnlyCombo = true, AddIgnoreCombo = true, AddAllies = true, AddOwnMaxHealth = true, AddAllyMaxHealth = true, DefaultHealthValue = 20 } },
    ["Taric"] = { Slot = SpellSlots.W, CastType = CastType.Targeted, Name = "Bastion", Range = 800, Config = { AddOnlyCombo = true, AddIgnoreCombo = true, AddAllies = true, AddOwnMaxHealth = true, AddAllyMaxHealth = true, DefaultHealthValue = 20 } },
    ["Nami"] = { Slot = SpellSlots.E, CastType = CastType.Targeted, Name = "Tidecaller's Blessing", Range = 800, Config = { AddOnlyCombo = true, AddAllies = true, AddOnAttack = true } }
}

local AutoJumpData = {
    ["LeeSin"] = { Slot = SpellSlots.W, CastType = CastType.Targeted, DisplayName = "Safeguard", CastRange = 700, Config = { Ward = true, AllyMinion = true, Ally = true }, SpellName = "BlindMonkWOne" },
    ["Talon"] = { Slot = SpellSlots.Q, CastType = CastType.Targeted, DisplayName = "Noxian Diplomacy", CastRange = 575, Config = { EnemyMinion = true, Enemy = true, Jungle = true } },
    ["Jax"] = { Slot = SpellSlots.Q, CastType = CastType.Targeted, DisplayName = "Leap Strike", CastRange = 700, Config = { Ward = true, EnemyMinion = true, Enemy = true, AllyMinion = true, Ally = true, Jungle = true } },
    ["Katarina"] = { Slot = SpellSlots.E, CastType = CastType.Skillshot, DisplayName = "Shunpo", CastRange = 725, Config = { EnemyMinion = true, Enemy = true, AllyMinion = true, Ally = true, Jungle = true } },
}

local WardData = {
    [3859] = { DisplayName = "Targon's Buckler" },
    [3860] = { DisplayName = "Bulwark of the Mountain" },
    [3855] = { DisplayName = "Runesteel Spaulders" },
    [3857] = { DisplayName = "Pauldrons of Whiterock" },
    [3851] = { DisplayName = "Frostfang" },
    [3853] = { DisplayName = "Shard of True Ice" },
    [3863] = { DisplayName = "Harrowing Crescent" },
    [3864] = { DisplayName = "Black Mist Scythe" },
    [3340] = { DisplayName = "Stealth Ward" },
    [2055] = { DisplayName = "Control Ward" },
}

local ItemData = {
    --// Cleanse Items //--
    [ItemID.MikaelsBlessing]                = { Type = ItemType.Cleanse,    CastType = CastType.Targeted,       CastRange = 650,    EffectRadius = 0,   Name = "Mikael's Blessing",         Config = { AddOnlyCombo = true, AddAllies = true, AddAllyDebuffs = true, AddDelay = true }, },
    [ItemID.QuicksilverSash]                = { Type = ItemType.Cleanse,    CastType = CastType.Active,         CastRange = 0,      EffectRadius = 0,   Name = "Quicksilver Sash",          Config = { AddOnlyCombo = true, AddDebuffs = true, AddDelay = true }, },
    [ItemID.MercurialScimitar]              = { Type = ItemType.Cleanse,    CastType = CastType.Active,         CastRange = 0,      EffectRadius = 0,   Name = "Mercurial Scimitar",        Config = { AddOnlyCombo = true, AddDebuffs = true, AddDelay = true }, },
    [ItemID.SilvermereDawn]                 = { Type = ItemType.Cleanse,    CastType = CastType.Active,         CastRange = 0,      EffectRadius = 0,   Name = "Silvermere Dawn",           Config = { AddOnlyCombo = true, AddDebuffs = true, AddDelay = true }, },

    --// Defensive Items //--
    [ItemID.RanduinsOmen]                   = { Type = ItemType.Defensive,  CastType = CastType.Active,         CastRange = 0,      EffectRadius = 400, Name = "Randuin's Omen",            Config = { AddOnlyCombo = true, AddEnemyCount = true } },
    [ItemID.LocketOftheIronSolari]          = { Type = ItemType.Defensive,  CastType = CastType.Active,         CastRange = 0,      EffectRadius = 800, Name = "Locket Of the Iron Solari", Config = { AddOnlyCombo = true, AddIgnoreCombo = true, AddAllies = true, AddOwnMaxHealth = true, AddAllyMaxHealth = true, DefaultHealthValue = 20 }},
    [ItemID.GargoyleStoneplate]             = { Type = ItemType.Defensive,  CastType = CastType.Active,         CastRange = 0,      EffectRadius = 0,   Name = "Gargoyle Stoneplate",       Config = { AddOnlyCombo = true, AddIgnoreCombo = true, AddOwnMaxHealth = true, DefaultHealthValue = 15 } },
    [ItemID.Redemption]                     = { Type = ItemType.Defensive,  CastType = CastType.Skillshot,      CastRange = 5500,   EffectRadius = 550, Name = "Redemption",                Config = { AddAllies = true, AddAllyMaxHealth = true }, PredictionInput = { Range = 5500, Delay = 2.5, Speed = math.huge, Radius = 550, Type = "Circular" } },
    [ItemID.Stopwatch]                      = { Type = ItemType.Defensive,  CastType = CastType.Active,         CastRange = 0,      EffectRadius = 0,   Name = "Stopwatch",                 Config = { AddOwnMaxHealth = true, DefaultHealthValue = 10 } },
    [ItemID.ZhonyasHourglass]               = { Type = ItemType.Defensive,  CastType = CastType.Active,         CastRange = 0,      EffectRadius = 0,   Name = "Zhonya's Hourglass",        Config = { AddOwnMaxHealth = true, DefaultHealthValue = 10 } },

    --// Offensive Items //--
    [ItemID.ProwlersClaw]                   = { Type = ItemType.Offensive,  CastType = CastType.Targeted,       CastRange = 500,    EffectRadius = 0,   Name = "Prowler's Claw",            Config = { AddOnlyCombo = true, AddEnemyMaxHealth = true, DefaultHealthValue = 100 } },
    [ItemID.IronspikeWhip]                  = { Type = ItemType.Offensive,  CastType = CastType.Active,         CastRange = 0,      EffectRadius = 325, Name = "Ironspike Whip",            Config = { AddOnlyCombo = true, AddEnemyMaxHealth = true, DefaultHealthValue = 100 } },
    [ItemID.Goredrinker]                    = { Type = ItemType.Offensive,  CastType = CastType.Active,         CastRange = 0,      EffectRadius = 325, Name = "Goredrinker",               Config = { AddOnlyCombo = true, AddEnemyMaxHealth = true, DefaultHealthValue = 100 } },
    [6631]                                  = { Type = ItemType.Offensive,  CastType = CastType.Active,         CastRange = 0,      EffectRadius = 325, Name = "Stridebreaker",             Config = { AddOnlyCombo = true, AddEnemyMaxHealth = true, DefaultHealthValue = 100 } },
    [ItemID.TurboChemtank]                  = { Type = ItemType.Offensive,  CastType = CastType.Active,         CastRange = 0,      EffectRadius = 700, Name = "Turbo Chemtank",            Config = { AddOnlyCombo = true } },
    [ItemID.Everfrost]                      = { Type = ItemType.Offensive,  CastType = CastType.Skillshot,      CastRange = 900,    EffectRadius = 0,   Name = "Everfrost",                 Config = { AddOnlyCombo = true, AddEnemyMaxHealth = true, DefaultHealthValue = 100 }, PredictionInput = { Range = 900, Delay = 1, Speed = math.huge, Radius = 200, Type = "Linear" } },
    [ItemID.HextechRocketbelt]              = { Type = ItemType.Offensive,  CastType = CastType.Skillshot,      CastRange = 1000,   EffectRadius = 275, Name = "Hextech Rocketbelt",        Config = { AddOnlyCombo = true }, PredictionInput = { Range = 1000, Delay = 0, Speed = math.huge, Radius = 275, Type = "Linear" } },
    [ItemID.YoumuusGhostblade]              = { Type = ItemType.Offensive,  CastType = CastType.Active,         CastRange = 0,      EffectRadius = 1000,Name = "Youmuus Ghostblade",        Config = { AddOnlyCombo = true } },
    [ItemID.ShurelyasBattlesong]            = { Type = ItemType.Offensive,  CastType = CastType.Active,         CastRange = 0,      EffectRadius = 1000,Name = "Shurelya's Battlesong",     Config = { AddOnlyCombo = true, AddAllyCount = true } },

    --// Consumable Items //--
    [ItemID.RefillablePotion]               = { Type = ItemType.Consumable, CastType = CastType.Active,         CastRange = 0,      EffectRadius = 0,   Name = "Refillable Potion",         Config = { AddOwnMaxHealth = true, DefaultHealthValue = 80 } },
    [ItemID.CorruptingPotion]               = { Type = ItemType.Consumable, CastType = CastType.Active,         CastRange = 0,      EffectRadius = 0,   Name = "Corrupting Potion",         Config = { AddOnlyCombo = true, AddOwnMaxHealth = true, DefaultHealthValue = 40 } },
    [ItemID.TotalBiscuitOfEverlastingWill]  = { Type = ItemType.Consumable, CastType = CastType.Active,         CastRange = 0,      EffectRadius = 0,   Name = "Total Biscuit",             Config = { AddOnlyCombo = true, AddOwnMaxHealth = true, DefaultHealthValue = 40 } },
    [ItemID.HealthPotion]                   = { Type = ItemType.Consumable, CastType = CastType.Active,         CastRange = 0,      EffectRadius = 0,   Name = "Health Potion",             Config = { AddOnlyCombo = true, AddOwnMaxHealth = true, DefaultHealthValue = 70 } },

    --// Instant Items //--
    [ItemID.OraclesExtract]                 = { Type = ItemType.Instant,    CastType = CastType.Active,         CastRange = 0,      EffectRadius = 0,   Name = "Oracle's Extract",          Config = {} },
    [ItemID.ElixirOfWrath]                  = { Type = ItemType.Instant,    CastType = CastType.Active,         CastRange = 0,      EffectRadius = 0,   Name = "Elixir Of Wrath",           Config = {} },
    [ItemID.ElixirOfSorcery]                = { Type = ItemType.Instant,    CastType = CastType.Active,         CastRange = 0,      EffectRadius = 0,   Name = "Elixir Of Sorcery",         Config = {} },
    [ItemID.ElixirOfIron]                   = { Type = ItemType.Instant,    CastType = CastType.Active,         CastRange = 0,      EffectRadius = 0,   Name = "Elixir Of Iron",            Config = {} },
    [ItemID.YourCut]                        = { Type = ItemType.Instant,    CastType = CastType.Active,         CastRange = 0,      EffectRadius = 0,   Name = "Your Cut (Pyke)",           Config = {} },
}

local DebuffData = {
    Ahri =          {{ Name = 'ahriseducedoom',         Type = BuffType.Charm,  Slot = SpellSlots.E }},
    Alistar =       {{ Name = 'Stun',                   Type = BuffType.Stun,   Slot = SpellSlots.E }},
    Amumu =         {{ Name = 'Stun',                   Type = BuffType.Stun,   Slot = SpellSlots.Q }, { Name = 'CurseoftheSadMummy',Type = BuffType.Snare,Slot = SpellSlots.R }},
    Anivia =        {{ Name = 'aniviaiced',             Type = BuffType.Stun,   Slot = SpellSlots.Q }},
    Annie =         {{ Name = 'anniepassivestun',       Type = BuffType.Stun,   Slot = -1 }},
    Ashe =          {{ Name = 'AsheR',                  Type = BuffType.Stun,   Slot = SpellSlots.R }},
    AurelionSol =   {{ Name = 'aurelionsolqstun',       Type = BuffType.Stun,   Slot = SpellSlots.Q }},
    Bard =          {{ Name = 'BardQSchacleDebuff',     Type = BuffType.Stun,   Slot = SpellSlots.Q }},
    Blitzcrank =    {{ Name = 'Silence',                Type = BuffType.Silence,Slot = SpellSlots.R }},
    Brand =         {{ Name = 'Stun',                   Type = BuffType.Stun,   Slot = SpellSlots.Q }},
    Braum =         {{ Name = 'braumstundebuff',        Type = BuffType.Stun,   Slot = -1 }},
    Caitlyn =       {{ Name = 'caitlynyordletrapdebuff',Type = BuffType.Snare,  Slot = SpellSlots.W }},
    Camille =       {{ Name = 'camilleestun',           Type = BuffType.Stun,   Slot = SpellSlots.E }},
    Cassiopeia =    {{ Name = 'CassiopeiaRStun',        Type = BuffType.Stun,   Slot = SpellSlots.R }},
    Chogath =       {{ Name = 'Silence',                Type = BuffType.Silence,Slot = SpellSlots.W }},
    Ekko =          {{ Name = 'ekkowstun',              Type = BuffType.Stun,   Slot = SpellSlots.W }},
    Elise =         {{ Name = 'EliseHumanE',            Type = BuffType.Stun,   Slot = SpellSlots.E }},
    Evelynn =       {{ Name = 'Charm',                  Type = BuffType.Charm,  Slot = SpellSlots.W }},
    FiddleSticks =  {{ Name = 'Flee',                   Type = BuffType.Flee,   Slot = SpellSlots.Q }, { Name = 'DarkWind',Type = BuffType.Silence,Slot = SpellSlots.E }},
    Fiora =         {{ Name = 'fiorawstun',             Type = BuffType.Stun,   Slot = SpellSlots.W }},
    Galio =         {{ Name = 'Taunt',                  Type = BuffType.Taunt,  Slot = SpellSlots.W }},
    Garen =         {{ Name = 'Silence',                Type = BuffType.Silence,Slot = SpellSlots.Q }},
    Gnar =          {{ Name = 'gnarstun',               Type = BuffType.Stun,   Slot = SpellSlots.W }, { Name = 'gnarknockbackcc',Type = BuffType.Stun, Slot = SpellSlots.R }},
    Hecarim =       {{ Name = 'HecarimUltMissileGrab',  Type = BuffType.Flee,   Slot = SpellSlots.R }},
    Heimerdinger =  {{ Name = 'HeimerdingerESpell',     Type = BuffType.Stun,   Slot = SpellSlots.E }, { Name = 'HeimerdingerESpell_ult', Type = BuffType.Stun, Slot = SpellSlots.E, Display = 'Enchanted E' }},
    Irelia =        {{ Name = 'Stun',                   Type = BuffType.Stun,   Slot = SpellSlots.E }},
    Ivern =         {{ Name = 'IvernQ',                 Type = BuffType.Snare,  Slot = SpellSlots.Q }},
    Jax =           {{ Name = 'Stun',                   Type = BuffType.Stun,   Slot = SpellSlots.E }},
    Jhin =          {{ Name = 'JhinW',                  Type = BuffType.Snare,  Slot = SpellSlots.W }},
    Jinx =          {{ Name = 'JinxEMineSnare',         Type = BuffType.Snare,  Slot = SpellSlots.E }},
    Karma =         {{ Name = 'karmaspiritbindroot',    Type = BuffType.Snare,  Slot = SpellSlots.W }},
    Kennen =        {{ Name = 'KennenMoSDiminish',      Type = BuffType.Stun,   Slot = -1 }},
    Leblanc =       {{ Name = 'leblanceroot',           Type = BuffType.Snare,  Slot = SpellSlots.E }, { Name = 'leblancreroot', Type = BuffType.Snare, Slot = SpellSlots.E, Display = 'Enchanted E' }},
    Leona =         {{ Name = 'Stun',                   Type = BuffType.Stun,   Slot = SpellSlots.Q }},
    Lissandra =     {{ Name = 'LissandraWFrozen',       Type = BuffType.Snare,  Slot = SpellSlots.W }, { Name = 'LissandraREnemy2', Type = BuffType.Stun, Slot = SpellSlots.R }},
    Lulu =          {{ Name = 'LuluWTwo',               Type = BuffType.Polymorph, Slot = SpellSlots.W }},
    Lux =           {{ Name = 'LuxLightBindingMis',     Type = BuffType.Snare,  Slot = SpellSlots.Q }},
    Malzahar =      {{ Name = 'MalzaharQMissile',       Type = BuffType.Silence,Slot = SpellSlots.Q }, { Name = 'MalzaharR', Type = BuffType.Suppression, Slot = SpellSlots.R }},
    Maokai =        {{ Name = 'maokaiwroot',            Type = BuffType.Snare,  Slot = SpellSlots.W }, { Name = 'maokairroot', Type = BuffType.Snare, Slot = SpellSlots.R }},
    Mordekaiser =   {{ Name = 'MordekaiserR',           Type = BuffType.CombatDehancer, Slot = SpellSlots.R }},
    Morgana =       {{ Name = 'MorganaQ',               Type = BuffType.Snare,  Slot = SpellSlots.Q }, { Name = 'morganarstun', Type = BuffType.Stun, Slot = SpellSlots.R }},
    Nami =          {{ Name = 'NamiQDebuff',            Type = BuffType.Stun,   Slot = SpellSlots.Q }},
    Nasus =         {{ Name = 'NasusW',                 Type = BuffType.Slow,   Slot = SpellSlots.W }},
    Nautilus =      {{ Name = 'nautiluspassiveroot',    Type = BuffType.Stun,   Slot = -1 }, { Name = 'nautilusanchordragroot', Type = BuffType.Snare, Slot = SpellSlots.R }},
    Neeko =         {{ Name = 'neekoeroot',             Type = BuffType.Snare,  Slot = SpellSlots.E }, { Name = 'neekorstun', Type = BuffType.Stun, Slot = SpellSlots.R }},
    Nocture =       {{ Name = 'Flee',                   Type = BuffType.Flee,   Slot = SpellSlots.E }},
    Nunu =          {{ Name = 'Stun',                   Type = BuffType.Stun,   Slot = SpellSlots.W }},
    Pantheon =      {{ Name = 'Stun',                   Type = BuffType.Stun,   Slot = SpellSlots.W }},
    Poppy =         {{ Name = 'Stun',                   Type = BuffType.Stun,   Slot = SpellSlots.E }},
    Pyke =          {{ Name = 'PykeEMissile',           Type = BuffType.Stun,   Slot = SpellSlots.E }},
    Qiyana =        {{ Name = 'qiyanarstun',            Type = BuffType.Stun,   Slot = SpellSlots.R }, { Name = 'qiyanaqroot', Type = BuffType.Snare, Slot = SpellSlots.Q }},
    Rakan =         {{ Name = 'rakanrdebuff',           Type = BuffType.Charm,  Slot = SpellSlots.R }},
    Rammus =        {{ Name = 'Taunt',                  Type = BuffType.Taunt,  Slot = SpellSlots.E }},
    Renekton =      {{ Name = 'Stun',                   Type = BuffType.Stun,   Slot = SpellSlots.W }},
    Rengar =        {{ Name = 'RengarEEmp',             Type = BuffType.Snare,  Slot = SpellSlots.E }},
    Riven =         {{ Name = 'Stun',                   Type = BuffType.Stun,   Slot = SpellSlots.W }},
    Ryze =          {{ Name = 'RyzeW',                  Type = BuffType.Snare,  Slot = SpellSlots.W }},
    Sejuani =       {{ Name = 'sejuanistun',            Type = BuffType.Stun,   Slot = SpellSlots.R }},
    Shaco =         {{ Name = 'shacoboxsnare',          Type = BuffType.Snare,  Slot = SpellSlots.W }},
    Shen =          {{ Name = 'Taunt',                  Type = BuffType.Taunt,  Slot = SpellSlots.E }},
    Skarner =       {{ Name = 'skarnerpassivestun',     Type = BuffType.Stun,   Slot = -1 }, { Name = 'suppression', Type = BuffType.Stun, Slot = SpellSlots.R }},
    Sona =          {{ Name = 'SonaR',                  Type = BuffType.Stun,   Slot = SpellSlots.R }},
    Soraka =        {{ Name = 'sorakaesnare',           Type = BuffType.Snare,  Slot = SpellSlots.E }},
    Sylas =         {{ Name = 'Stun',                   Type = BuffType.Stun,   Slot = SpellSlots.E }},
    Swain =         {{ Name = 'swaineroot',             Type = BuffType.Snare,  Slot = SpellSlots.E }},
    Syndra =        {{ Name = 'syndraebump',            Type = BuffType.Stun,   Slot = SpellSlots.E }},
    TahmKench =     {{ Name = 'tahmkenchqstun',         Type = BuffType.Stun,   Slot = SpellSlots.Q }, { Name = 'tahmkenchwdevoured', Type = BuffType.Suppression, Slot = SpellSlots.W }},
    Taric =         {{ Name = 'taricestun',             Type = BuffType.Stun,   Slot = SpellSlots.E }},
    Teemo =         {{ Name = 'BlindingDart',           Type = BuffType.Stun,   Slot = SpellSlots.Q }},
    Thresh =        {{ Name = 'threshqfakeknockup',     Type = BuffType.Knockup,Slot = SpellSlots.Q }, { Name = 'threshrslow', Type = BuffType.Slow, Slot = SpellSlots.R }},
    Tryndamere =    {{ Name = 'tryndamerewslow',        Type = BuffType.Slow,   Slot = SpellSlots.W }},
    TwistedFate =   {{ Name = 'Stun',                   Type = BuffType.Stun,   Slot = SpellSlots.E }},
    Udyr =          {{ Name = 'Stun',                   Type = BuffType.Stun,   Slot = SpellSlots.E }},
    Urgot =         {{ Name = 'urgotrfear',             Type = BuffType.Fear,   Slot = SpellSlots.R }},
    Varus =         {{ Name = 'varusrroot',             Type = BuffType.Snare,  Slot = SpellSlots.R }},
    Vayne =         {{ Name = 'VayneCondemnMissile',    Type = BuffType.Stun,   Slot = SpellSlots.E }},
    Veigar =        {{ Name = 'veigareventhorizonstun', Type = BuffType.Stun,   Slot = SpellSlots.E }},
    Viktor =        {{ Name = 'viktorgravitonfieldstun',Type = BuffType.Stun,   Slot = SpellSlots.W }, { Name = 'viktorwaugstun', Type = BuffType.Stun, Slot = SpellSlots.W }},
    Warwick =       {{ Name = 'Flee',                   Type = BuffType.Flee,   Slot = SpellSlots.E }, { Name = 'suppression', Type = BuffType.Suppression, Slot = SpellSlots.R }},
    Xayah =         {{ Name = 'XayahE',                 Type = BuffType.Snare,  Slot = SpellSlots.E }},
    Xerath =        {{ Name = 'Stun',                   Type = BuffType.Stun,   Slot = SpellSlots.E }},
    Yuumi =         {{ Name = 'yuumircc',               Type = BuffType.Snare,  Slot = SpellSlots.R }},
    Yasuo =         {{ Name = 'yasuorknockup',          Type = BuffType.Knockup,Slot = SpellSlots.R }},
    Zac =           {{ Name = 'zacqyankroot',           Type = BuffType.Snare,  Slot = SpellSlots.Q }, { Name = 'zachitstun', Type = BuffType.Stun, Slot = SpellSlots.E }},
    Zilean =        {{ Name = 'ZileanStunAnim',         Type = BuffType.Stun,   Slot = SpellSlots.Q }, { Name = 'timewarpslow', Type = BuffType.Slow, Slot = SpellSlots.E }},
    Zoe =           {{ Name = 'zoeesleepstun',          Type = BuffType.Stun,   Slot = SpellSlots.E }},
    Zyra =          {{ Name = 'zyraehold',              Type = BuffType.Snare,  Slot = SpellSlots.E }},
    Senna =         {{ Name = 'sennawroot',             Type = BuffType.Snare,  Slot = SpellSlots.W }},
    Lillia =        {{ Name = 'LilliaRSleep',           Type = BuffType.Drowsy, Slot = SpellSlots.R }},
    Sett =          {{ Name = 'Stun',                   Type = BuffType.Stun, Slot = SpellSlots.E }},
    Yone =          {{ Name = 'yonerstun',              Type = BuffType.Stun, Slot = SpellSlots.R }},
    Viego =         {{ Name = 'ViegoWMis',              Type = BuffType.Stun, Slot = SpellSlots.W }},
    Sylas =         {{ Name = 'Stun',                   Type = BuffType.Stun, Slot = SpellSlots.E }},
    Seraphine =     {{ Name = 'SeraphineERoot',         Type = BuffType.Snare, Slot = SpellSlots.E }, { Name = 'seraphineestun', Type = BuffType.Stun, Slot = SpellSlots.E }},
    Rell =          {{ Name = 'rellestun',              Type = BuffType.Stun, Slot = SpellSlots.E }, { Name = 'Stun', Type = BuffType.Stun, Slot = SpellSlots.W }},
    Aphelios =      {{ Name = 'ApheliosGravitumRoot',   Type = BuffType.Snare, Slot = SpellSlots.Q }},
}

local LevelPresets = {
    ["Aatrox"] = {
        ["mostUsed"] = {"Q", "E", "W", "Q", "Q", "R", "Q", "E", "Q", "E", "R", "E", "E", "W", "W", "R", "W", "W"},
        ["highestRate"] = {"Q", "E", "W", "Q", "Q", "R", "Q", "E", "E", "Q", "R", "E", "E", "W", "W", "R", "W", "W"}
    },
    ["Ahri"] = {
        ["mostUsed"] = {"Q", "E", "W", "Q", "Q", "R", "Q", "W", "Q", "W", "R", "W", "W", "E", "E", "R", "E", "E"},
        ["highestRate"] = {"W", "E", "Q", "Q", "Q", "R", "Q", "W", "Q", "W", "R", "W", "W", "E", "E", "R", "E", "E"}
    },
    ["Akali"] = {
        ["mostUsed"] = {"Q", "E", "Q", "W", "Q", "R", "Q", "E", "Q", "E", "R", "E", "E", "W", "W", "R", "W", "W"},
        ["highestRate"] = {"Q", "E", "Q", "W", "Q", "R", "Q", "E", "Q", "E", "R", "E", "E", "W", "W", "R", "W", "W"}
    },
    ["Akshan"] = {
        ["mostUsed"] = {"Q", "E", "W", "Q", "Q", "R", "Q", "E", "Q", "E", "R", "E", "E", "W", "W", "R", "W", "W"},
        ["highestRate"] = {"Q", "W", "E", "Q", "Q", "R", "Q", "W", "Q", "E", "R", "E", "E", "E", "W", "R", "W", "W"}
    },
    ["Alistar"] = {
        ["mostUsed"] = {"Q", "W", "E", "Q", "Q", "R", "Q", "W", "Q", "W", "R", "W", "W", "E", "E", "R", "E", "E"},
        ["highestRate"] = {"Q", "W", "E", "Q", "Q", "R", "Q", "W", "Q", "E", "R", "W", "W", "W", "E", "R", "E", "E"}
    },
    ["Amumu"] = {
        ["mostUsed"] = {"W", "E", "Q", "E", "E", "R", "E", "Q", "E", "Q", "R", "Q", "Q", "W", "W", "R", "W", "W"},
        ["highestRate"] = {"Q", "E", "W", "E", "E", "R", "E", "Q", "E", "Q", "R", "Q", "Q", "W", "W", "R", "W", "W"}
    },
    ["Anivia"] = {
        ["mostUsed"] = {"Q", "E", "E", "W", "E", "R", "E", "Q", "E", "Q", "R", "Q", "Q", "W", "W", "R", "W", "W"},
        ["highestRate"] = {"Q", "E", "E", "W", "E", "R", "E", "Q", "E", "Q", "R", "W", "Q", "Q", "W", "R", "W", "W"}
    },
    ["Annie"] = {
        ["mostUsed"] = {"Q", "W", "E", "Q", "Q", "R", "Q", "W", "Q", "W", "R", "W", "W", "E", "E", "R", "E", "E"},
        ["highestRate"] = {"Q", "W", "E", "Q", "Q", "R", "Q", "W", "Q", "W", "R", "W", "E", "W", "E", "R", "E", "E"}
    },
    ["Aphelios"] = {
        ["mostUsed"] = {"Q", "Q", "Q", "R", "Q", "R", "Q", "R", "Q", "R", "R", "R", "E", "E", "E", "E", "E", "E"},
        ["highestRate"] = {"Q", "R", "R", "R", "R", "W", "R", "W", "R", "Q", "Q", "Q", "E", "E", "E", "E", "E", "E"}
    },
    ["Ashe"] = {
        ["mostUsed"] = {"W", "Q", "E", "W", "W", "R", "W", "Q", "W", "Q", "R", "Q", "Q", "E", "E", "R", "E", "E"},
        ["highestRate"] = {"W", "E", "W", "Q", "W", "R", "W", "E", "W", "E", "R", "E", "E", "Q", "Q", "R", "Q", "Q"}
    },
    ["AurelionSol"] = {
        ["mostUsed"] = {"Q", "W", "E", "W", "W", "R", "W", "Q", "W", "Q", "R", "Q", "Q", "E", "E", "R", "E", "E"},
        ["highestRate"] = {"Q", "W", "E", "W", "W", "R", "W", "E", "W", "Q", "R", "Q", "Q", "Q", "E", "R", "E", "E"}
    },
    ["Azir"] = {
        ["mostUsed"] = {"W", "Q", "E", "Q", "Q", "R", "Q", "W", "Q", "W", "R", "W", "W", "E", "E", "R", "E", "E"},
        ["highestRate"] = {"W", "E", "Q", "Q", "Q", "R", "Q", "W", "Q", "W", "R", "W", "W", "E", "E", "R", "E", "E"}
    },
    ["Bard"] = {
        ["mostUsed"] = {"Q", "W", "E", "Q", "Q", "R", "Q", "W", "Q", "W", "R", "W", "W", "E", "E", "R", "E", "E"},
        ["highestRate"] = {"Q", "W", "E", "W", "Q", "R", "Q", "Q", "Q", "W", "R", "W", "W", "E", "E", "R", "E", "E"}
    },
    ["Belveth"] = {
        ["mostUsed"] = {"Q", "E", "W", "Q", "Q", "R", "Q", "E", "Q", "E", "R", "E", "E", "W", "W", "R", "W", "W"},
        ["highestRate"] = {"Q", "E", "W", "Q", "Q", "R", "Q", "E", "Q", "E", "R", "E", "E", "W", "W", "R", "W", "W"}
    },
    ["Blitzcrank"] = {
        ["mostUsed"] = {"Q", "E", "W", "Q", "Q", "R", "Q", "E", "Q", "E", "R", "E", "E", "W", "W", "R", "W", "W"},
        ["highestRate"] = {"Q", "E", "W", "Q", "Q", "R", "Q", "E", "Q", "E", "R", "E", "W", "E", "W", "R", "W", "W"}
    },
    ["Brand"] = {
        ["mostUsed"] = {"W", "Q", "E", "W", "W", "R", "W", "Q", "W", "Q", "R", "Q", "Q", "E", "E", "R", "E", "E"},
        ["highestRate"] = {"W", "Q", "E", "W", "W", "R", "W", "Q", "W", "Q", "R", "E", "Q", "Q", "E", "R", "E", "E"}
    },
    ["Braum"] = {
        ["mostUsed"] = {"Q", "E", "W", "Q", "Q", "R", "Q", "E", "Q", "E", "R", "E", "E", "W", "W", "R", "W", "W"},
        ["highestRate"] = {"Q", "E", "W", "Q", "Q", "R", "Q", "E", "E", "Q", "R", "E", "E", "W", "W", "R", "W", "W"}
    },
    ["Caitlyn"] = {
        ["mostUsed"] = {"Q", "W", "E", "Q", "Q", "R", "Q", "W", "Q", "W", "R", "W", "W", "E", "E", "R", "E", "E"},
        ["highestRate"] = {"Q", "W", "E", "Q", "Q", "R", "W", "W", "W", "W", "R", "Q", "Q", "E", "E", "R", "E", "E"}
    },
    ["Camille"] = {
        ["mostUsed"] = {"W", "Q", "E", "Q", "Q", "R", "Q", "E", "Q", "E", "R", "E", "E", "W", "W", "R", "W", "W"},
        ["highestRate"] = {"E", "Q", "W", "Q", "Q", "R", "Q", "E", "Q", "E", "R", "E", "E", "W", "W", "R", "W", "W"}
    },
    ["Cassiopeia"] = {
        ["mostUsed"] = {"E", "Q", "W", "E", "E", "R", "E", "Q", "E", "Q", "R", "Q", "Q", "W", "W", "R", "W", "W"},
        ["highestRate"] = {"E", "Q", "W", "E", "E", "R", "Q", "E", "E", "Q", "R", "Q", "Q", "W", "W", "R", "W", "W"}
    },
    ["Chogath"] = {
        ["mostUsed"] = {"E", "Q", "W", "E", "E", "R", "E", "W", "E", "W", "R", "W", "W", "Q", "Q", "R", "Q", "Q"},
        ["highestRate"] = {"Q", "E", "W", "Q", "Q", "R", "Q", "W", "Q", "W", "R", "W", "W", "E", "E", "R", "E", "E"}
    },
    ["Corki"] = {
        ["mostUsed"] = {"Q", "E", "W", "Q", "Q", "R", "Q", "E", "Q", "E", "R", "E", "E", "W", "W", "R", "W", "W"},
        ["highestRate"] = {"Q", "W", "E", "Q", "Q", "R", "Q", "W", "Q", "W", "R", "W", "W", "E", "E", "R", "E", "E"}
    },
    ["Darius"] = {
        ["mostUsed"] = {"Q", "W", "E", "Q", "Q", "R", "Q", "E", "Q", "E", "R", "E", "E", "W", "W", "R", "W", "W"},
        ["highestRate"] = {"Q", "W", "Q", "E", "Q", "R", "Q", "E", "Q", "E", "R", "E", "E", "W", "W", "R", "W", "W"}
    },
    ["Diana"] = {
        ["mostUsed"] = {"Q", "W", "E", "Q", "Q", "R", "Q", "W", "Q", "W", "R", "W", "W", "E", "E", "R", "E", "E"},
        ["highestRate"] = {"Q", "W", "E", "Q", "Q", "R", "Q", "E", "Q", "W", "R", "W", "W", "W", "E", "R", "E", "E"}
    },
    ["DrMundo"] = {
        ["mostUsed"] = {"E", "W", "Q", "E", "E", "R", "E", "Q", "E", "Q", "R", "Q", "Q", "W", "W", "R", "W", "W"},
        ["highestRate"] = {"E", "W", "Q", "Q", "Q", "R", "Q", "E", "Q", "E", "R", "E", "E", "W", "W", "R", "W", "W"}
    },
    ["Draven"] = {
        ["mostUsed"] = {"Q", "W", "E", "Q", "Q", "R", "Q", "W", "Q", "W", "R", "W", "W", "E", "E", "R", "E", "E"},
        ["highestRate"] = {"Q", "W", "E", "Q", "Q", "R", "Q", "W", "Q", "W", "R", "E", "W", "W", "E", "R", "E", "E"}
    },
    ["Ekko"] = {
        ["mostUsed"] = {"Q", "E", "W", "Q", "Q", "R", "Q", "E", "Q", "E", "R", "E", "E", "W", "W", "R", "W", "W"},
        ["highestRate"] = {"Q", "E", "W", "Q", "Q", "Q", "R", "E", "Q", "E", "R", "E", "E", "W", "W", "R", "W", "W"}
    },
    ["Elise"] = {
        ["mostUsed"] = {"W", "Q", "E", "Q", "Q", "R", "Q", "W", "Q", "W", "R", "W", "W", "E", "E", "R", "E", "E"},
        ["highestRate"] = {"E", "Q", "W", "Q", "Q", "R", "Q", "W", "Q", "W", "R", "W", "W", "E", "E", "R", "E", "E"}
    },
    ["Evelynn"] = {
        ["mostUsed"] = {"Q", "W", "E", "Q", "Q", "R", "Q", "E", "Q", "E", "R", "E", "E", "W", "W", "R", "W", "W"},
        ["highestRate"] = {"Q", "E", "Q", "W", "Q", "R", "Q", "E", "Q", "E", "R", "E", "E", "W", "W", "R", "W", "W"}
    },
    ["Ezreal"] = {
        ["mostUsed"] = {"Q", "E", "W", "Q", "Q", "R", "Q", "E", "Q", "E", "R", "E", "E", "W", "W", "R", "W", "W"},
        ["highestRate"] = {"Q", "E", "W", "Q", "Q", "R", "Q", "E", "Q", "W", "R", "E", "E", "E", "W", "R", "W", "W"}
    },
    ["Fiddlesticks"] = {
        ["mostUsed"] = {"W", "E", "W", "Q", "W", "R", "W", "Q", "W", "Q", "R", "Q", "Q", "E", "E", "R", "E", "E"},
        ["highestRate"] = {"E", "W", "Q", "W", "W", "R", "W", "Q", "W", "Q", "R", "Q", "Q", "E", "E", "R", "E", "E"}
    },
    ["Fiora"] = {
        ["mostUsed"] = {"Q", "W", "E", "Q", "Q", "R", "Q", "E", "Q", "E", "R", "E", "E", "W", "W", "R", "W", "W"},
        ["highestRate"] = {"Q", "W", "E", "Q", "Q", "R", "Q", "E", "Q", "E", "R", "W", "E", "E", "W", "R", "W", "W"}
    },
    ["Fizz"] = {
        ["mostUsed"] = {"E", "W", "Q", "E", "E", "R", "E", "W", "E", "W", "R", "W", "W", "Q", "Q", "R", "Q", "Q"},
        ["highestRate"] = {"W", "E", "Q", "W", "E", "R", "E", "E", "E", "W", "R", "W", "W", "Q", "Q", "R", "Q", "Q"}
    },
    ["Galio"] = {
        ["mostUsed"] = {"Q", "W", "E", "Q", "Q", "R", "Q", "W", "Q", "W", "R", "W", "W", "E", "E", "R", "E", "E"},
        ["highestRate"] = {"E", "W", "Q", "W", "W", "R", "W", "E", "W", "E", "R", "E", "E", "Q", "Q", "R", "Q", "Q"}
    },
    ["Gangplank"] = {
        ["mostUsed"] = {"Q", "E", "W", "Q", "Q", "R", "Q", "E", "Q", "E", "R", "E", "E", "W", "W", "R", "W", "W"},
        ["highestRate"] = {"Q", "E", "W", "Q", "Q", "R", "Q", "E", "Q", "E", "R", "E", "E", "W", "W", "W", "R", "W"}
    },
    ["Garen"] = {
        ["mostUsed"] = {"Q", "E", "W", "E", "E", "R", "E", "Q", "E", "Q", "R", "Q", "Q", "W", "W", "R", "W", "W"},
        ["highestRate"] = {"Q", "E", "E", "W", "E", "R", "E", "Q", "E", "Q", "R", "Q", "Q", "W", "W", "R", "W", "W"}
    },
    ["Gnar"] = {
        ["mostUsed"] = {"Q", "W", "E", "Q", "Q", "R", "Q", "W", "Q", "W", "R", "W", "W", "E", "E", "R", "E", "E"},
        ["highestRate"] = {"E", "Q", "W", "Q", "Q", "R", "Q", "W", "Q", "W", "R", "W", "W", "E", "E", "R", "E", "E"}
    },
    ["Gragas"] = {
        ["mostUsed"] = {"W", "Q", "E", "Q", "Q", "R", "Q", "E", "Q", "E", "R", "E", "E", "W", "W", "R", "W", "W"},
        ["highestRate"] = {"E", "W", "Q", "E", "E", "R", "E", "W", "E", "W", "R", "W", "W", "Q", "Q", "R", "Q", "Q"}
    },
    ["Graves"] = {
        ["mostUsed"] = {"E", "Q", "W", "Q", "Q", "R", "Q", "E", "Q", "E", "R", "E", "E", "W", "W", "R", "W", "W"},
        ["highestRate"] = {"E", "Q", "Q", "W", "Q", "R", "Q", "E", "Q", "E", "R", "E", "E", "W", "W", "R", "W", "W"}
    },
    ["Gwen"] = {
        ["mostUsed"] = {"E", "Q", "W", "Q", "Q", "R", "Q", "E", "Q", "E", "R", "E", "E", "W", "W", "R", "W", "W"},
        ["highestRate"] = {"E", "Q", "Q", "W", "Q", "R", "Q", "E", "Q", "E", "R", "E", "E", "W", "W", "R", "W", "W"}
    },
    ["Hecarim"] = {
        ["mostUsed"] = {"Q", "W", "E", "Q", "Q", "R", "Q", "E", "Q", "E", "R", "E", "E", "W", "W", "R", "W", "W"},
        ["highestRate"] = {"Q", "W", "E", "Q", "Q", "R", "Q", "E", "Q", "E", "R", "E", "W", "E", "W", "R", "W", "W"}
    },
    ["Heimerdinger"] = {
        ["mostUsed"] = {"Q", "E", "W", "W", "W", "R", "W", "Q", "W", "Q", "R", "Q", "Q", "E", "E", "R", "E", "E"},
        ["highestRate"] = {"Q", "E", "W", "W", "W", "R", "W", "E", "W", "E", "R", "E", "E", "Q", "Q", "R", "Q", "Q"}
    },
    ["Illaoi"] = {
        ["mostUsed"] = {"Q", "W", "E", "E", "E", "R", "E", "Q", "E", "Q", "R", "Q", "Q", "W", "W", "R", "W", "W"},
        ["highestRate"] = {"Q", "W", "E", "Q", "Q", "R", "Q", "E", "Q", "E", "R", "E", "E", "W", "W", "R", "W", "W"}
    },
    ["Irelia"] = {
        ["mostUsed"] = {"Q", "E", "W", "Q", "Q", "R", "Q", "E", "Q", "E", "R", "E", "E", "W", "W", "R", "W", "W"},
        ["highestRate"] = {"Q", "E", "W", "Q", "Q", "R", "Q", "E", "Q", "E", "R", "W", "E", "E", "W", "R", "W", "W"}
    },
    ["Ivern"] = {
        ["mostUsed"] = {"Q", "E", "W", "E", "E", "R", "E", "Q", "E", "Q", "R", "Q", "Q", "W", "W", "R", "W", "W"},
        ["highestRate"] = {"E", "Q", "E", "W", "E", "R", "E", "Q", "E", "Q", "R", "Q", "Q", "W", "W", "R", "W", "W"}
    },
    ["Janna"] = {
        ["mostUsed"] = {"W", "Q", "E", "W", "W", "R", "W", "E", "W", "E", "R", "E", "E", "Q", "Q", "R", "Q", "Q"},
        ["highestRate"] = {"W", "Q", "E", "W", "E", "R", "E", "E", "E", "W", "R", "W", "W", "Q", "Q", "R", "Q", "Q"}
    },
    ["JarvanIV"] = {
        ["mostUsed"] = {"E", "Q", "W", "Q", "Q", "R", "Q", "E", "Q", "E", "R", "E", "E", "W", "W", "R", "W", "W"},
        ["highestRate"] = {"E", "Q", "W", "Q", "Q", "R", "Q", "E", "Q", "E", "R", "E", "W", "E", "W", "R", "W", "W"}
    },
    ["Jax"] = {
        ["mostUsed"] = {"E", "Q", "W", "W", "W", "R", "W", "E", "W", "E", "R", "E", "E", "Q", "Q", "R", "Q", "Q"},
        ["highestRate"] = {"E", "Q", "W", "W", "W", "R", "W", "Q", "W", "E", "R", "E", "E", "E", "Q", "R", "Q", "Q"}
    },
    ["Jayce"] = {
        ["mostUsed"] = {"Q", "E", "W", "Q", "Q", "W", "Q", "W", "Q", "W", "Q", "W", "W", "E", "E", "E", "E", "E"},
        ["highestRate"] = {"Q", "W", "Q", "E", "Q", "W", "Q", "W", "Q", "W", "Q", "W", "W", "E", "E", "E", "E", "E"}
    },
    ["Jhin"] = {
        ["mostUsed"] = {"Q", "W", "E", "Q", "Q", "R", "Q", "W", "Q", "W", "R", "W", "W", "E", "E", "R", "E", "E"},
        ["highestRate"] = {"W", "Q", "Q", "E", "Q", "R", "Q", "W", "Q", "W", "R", "W", "W", "E", "E", "R", "E", "E"}
    },
    ["Jinx"] = {
        ["mostUsed"] = {"Q", "W", "E", "Q", "Q", "R", "Q", "W", "Q", "W", "R", "W", "W", "E", "E", "R", "E", "E"},
        ["highestRate"] = {"Q", "E", "Q", "W", "Q", "R", "Q", "W", "Q", "W", "R", "W", "W", "E", "E", "R", "E", "E"}
    },
    ["Kaisa"] = {
        ["mostUsed"] = {"Q", "W", "E", "Q", "Q", "R", "Q", "E", "Q", "E", "R", "E", "E", "W", "W", "R", "W", "W"},
        ["highestRate"] = {"Q", "W", "Q", "E", "Q", "R", "Q", "E", "Q", "E", "R", "E", "E", "W", "W", "R", "W", "W"}
    },
    ["Kalista"] = {
        ["mostUsed"] = {"E", "Q", "W", "E", "E", "R", "E", "Q", "E", "Q", "R", "Q", "Q", "W", "W", "R", "W", "W"},
        ["highestRate"] = {"E", "Q", "Q", "W", "Q", "R", "Q", "E", "Q", "E", "R", "E", "E", "W", "W", "R", "W", "W"}
    },
    ["Karma"] = {
        ["mostUsed"] = {"Q", "E", "W", "Q", "Q", "R", "Q", "E", "Q", "E", "R", "E", "E", "W", "W", "R", "W", "W"},
        ["highestRate"] = {"Q", "E", "W", "Q", "E", "R", "E", "E", "E", "Q", "R", "Q", "Q", "W", "W", "R", "W", "W"}
    },
    ["Karthus"] = {
        ["mostUsed"] = {"Q", "E", "Q", "W", "Q", "R", "Q", "E", "Q", "E", "R", "E", "E", "W", "W", "R", "W", "W"},
        ["highestRate"] = {"Q", "E", "Q", "W", "Q", "R", "Q", "E", "Q", "E", "R", "W", "E", "E", "W", "R", "W", "W"}
    },
    ["Kassadin"] = {
        ["mostUsed"] = {"Q", "W", "E", "Q", "Q", "R", "Q", "E", "Q", "E", "R", "E", "E", "W", "W", "R", "W", "W"},
        ["highestRate"] = {"Q", "W", "Q", "E", "Q", "R", "Q", "E", "Q", "E", "R", "E", "E", "W", "W", "R", "W", "W"}
    },
    ["Katarina"] = {
        ["mostUsed"] = {"Q", "E", "W", "Q", "Q", "R", "Q", "E", "Q", "E", "R", "E", "E", "W", "W", "R", "W", "W"},
        ["highestRate"] = {"Q", "E", "W", "Q", "Q", "R", "E", "Q", "Q", "E", "R", "E", "E", "W", "W", "R", "W", "W"}
    },
    ["Kayle"] = {
        ["mostUsed"] = {"E", "Q", "W", "E", "E", "R", "E", "Q", "E", "Q", "R", "Q", "Q", "W", "W", "R", "W", "W"},
        ["highestRate"] = {"E", "W", "Q", "Q", "Q", "R", "Q", "E", "Q", "E", "R", "E", "E", "W", "W", "R", "W", "W"}
    },
    ["Kayn"] = {
        ["mostUsed"] = {"Q", "E", "W", "Q", "Q", "R", "Q", "W", "Q", "W", "R", "W", "W", "E", "E", "R", "E", "E"},
        ["highestRate"] = {"Q", "E", "Q", "W", "Q", "R", "W", "W", "W", "W", "R", "Q", "Q", "E", "E", "R", "E", "E"}
    },
    ["Kennen"] = {
        ["mostUsed"] = {"Q", "W", "E", "Q", "Q", "R", "Q", "W", "Q", "W", "R", "W", "W", "E", "E", "R", "E", "E"},
        ["highestRate"] = {"Q", "E", "W", "Q", "Q", "R", "Q", "E", "Q", "E", "R", "E", "E", "W", "W", "R", "W", "W"}
    },
    ["Khazix"] = {
        ["mostUsed"] = {"Q", "W", "E", "Q", "Q", "R", "Q", "W", "Q", "W", "R", "W", "W", "E", "E", "R", "E", "E"},
        ["highestRate"] = {"Q", "W", "E", "Q", "Q", "R", "Q", "W", "Q", "W", "R", "W", "E", "W", "E", "R", "E", "E"}
    },
    ["Kindred"] = {
        ["mostUsed"] = {"W", "Q", "E", "Q", "Q", "R", "Q", "W", "Q", "W", "R", "W", "W", "E", "E", "R", "E", "E"},
        ["highestRate"] = {"W", "Q", "E", "Q", "Q", "R", "Q", "W", "Q", "W", "R", "E", "W", "W", "E", "R", "E", "E"}
    },
    ["Kled"] = {
        ["mostUsed"] = {"Q", "E", "W", "Q", "Q", "R", "Q", "W", "Q", "W", "R", "W", "W", "E", "E", "R", "E", "E"},
        ["highestRate"] = {"Q", "E", "W", "Q", "Q", "R", "Q", "W", "Q", "W", "R", "W", "E", "W", "E", "R", "E", "E"}
    },
    ["KogMaw"] = {
        ["mostUsed"] = {"W", "Q", "E", "W", "W", "R", "W", "Q", "W", "Q", "R", "Q", "Q", "E", "E", "R", "E", "E"},
        ["highestRate"] = {"W", "Q", "W", "Q", "W", "R", "W", "Q", "W", "Q", "R", "Q", "E", "E", "E", "R", "E", "E"}
    },
    ["Leblanc"] = {
        ["mostUsed"] = {"W", "Q", "E", "W", "W", "R", "W", "Q", "W", "Q", "R", "Q", "Q", "E", "E", "R", "E", "E"},
        ["highestRate"] = {"E", "W", "Q", "W", "W", "R", "W", "Q", "W", "Q", "R", "Q", "Q", "E", "E", "R", "E", "E"}
    },
    ["LeeSin"] = {
        ["mostUsed"] = {"W", "Q", "E", "Q", "Q", "R", "Q", "W", "Q", "W", "R", "W", "W", "E", "E", "R", "E", "E"},
        ["highestRate"] = {"Q", "E", "W", "E", "E", "R", "E", "Q", "E", "Q", "R", "Q", "Q", "W", "W", "R", "W", "W"}
    },
    ["Leona"] = {
        ["mostUsed"] = {"Q", "E", "W", "W", "W", "R", "W", "E", "W", "E", "R", "E", "E", "Q", "Q", "R", "Q", "Q"},
        ["highestRate"] = {"Q", "E", "W", "W", "W", "R", "W", "Q", "W", "E", "R", "E", "E", "E", "Q", "R", "Q", "Q"}
    },
    ["Lillia"] = {
        ["mostUsed"] = {"Q", "W", "E", "Q", "Q", "R", "Q", "E", "Q", "E", "R", "E", "E", "W", "W", "R", "W", "W"},
        ["highestRate"] = {"Q", "W", "E", "Q", "Q", "R", "Q", "E", "Q", "W", "R", "W", "W", "W", "E", "R", "E", "E"}
    },
    ["Lissandra"] = {
        ["mostUsed"] = {"Q", "W", "E", "Q", "Q", "R", "Q", "W", "Q", "W", "R", "W", "W", "E", "E", "R", "E", "E"},
        ["highestRate"] = {"Q", "W", "E", "Q", "Q", "R", "Q", "W", "Q", "W", "R", "W", "E", "W", "E", "R", "E", "E"}
    },
    ["Lucian"] = {
        ["mostUsed"] = {"Q", "E", "W", "Q", "Q", "R", "Q", "E", "Q", "E", "R", "E", "E", "W", "W", "R", "W", "W"},
        ["highestRate"] = {"Q", "E", "W", "Q", "Q", "R", "Q", "W", "Q", "E", "R", "E", "E", "E", "W", "R", "W", "W"}
    },
    ["Lulu"] = {
        ["mostUsed"] = {"E", "Q", "W", "E", "E", "R", "E", "W", "E", "W", "R", "W", "W", "Q", "Q", "R", "Q", "Q"},
        ["highestRate"] = {"E", "Q", "W", "E", "E", "R", "W", "W", "W", "W", "R", "E", "E", "Q", "Q", "R", "Q", "Q"}
    },
    ["Lux"] = {
        ["mostUsed"] = {"E", "Q", "W", "E", "E", "R", "E", "Q", "E", "Q", "R", "Q", "Q", "W", "W", "R", "W", "W"},
        ["highestRate"] = {"E", "Q", "W", "Q", "Q", "R", "Q", "E", "Q", "E", "R", "E", "E", "W", "W", "R", "W", "W"}
    },
    ["Malphite"] = {
        ["mostUsed"] = {"Q", "E", "W", "Q", "Q", "R", "Q", "E", "Q", "E", "R", "E", "E", "W", "W", "R", "W", "W"},
        ["highestRate"] = {"Q", "W", "Q", "E", "Q", "R", "Q", "W", "Q", "W", "R", "W", "W", "E", "E", "R", "E", "E"}
    },
    ["Malzahar"] = {
        ["mostUsed"] = {"E", "W", "Q", "E", "E", "R", "E", "Q", "E", "Q", "R", "Q", "Q", "W", "W", "R", "W", "W"},
        ["highestRate"] = {"E", "W", "E", "Q", "E", "R", "E", "Q", "E", "Q", "R", "Q", "Q", "W", "W", "R", "W", "W"}
    },
    ["Maokai"] = {
        ["mostUsed"] = {"Q", "W", "E", "Q", "Q", "R", "Q", "W", "Q", "W", "R", "W", "W", "E", "E", "R", "E", "E"},
        ["highestRate"] = {"E", "W", "Q", "E", "E", "R", "E", "Q", "E", "Q", "R", "Q", "Q", "W", "W", "R", "W", "W"}
    },
    ["MasterYi"] = {
        ["mostUsed"] = {"Q", "E", "W", "Q", "Q", "R", "Q", "E", "Q", "E", "R", "E", "E", "W", "W", "R", "W", "W"},
        ["highestRate"] = {"Q", "E", "W", "Q", "Q", "R", "E", "E", "E", "E", "R", "Q", "Q", "W", "W", "R", "W", "W"}
    },
    ["MissFortune"] = {
        ["mostUsed"] = {"Q", "W", "E", "Q", "Q", "R", "Q", "W", "Q", "W", "R", "W", "W", "E", "E", "R", "E", "E"},
        ["highestRate"] = {"Q", "E", "Q", "W", "Q", "R", "Q", "W", "Q", "W", "R", "W", "W", "E", "E", "R", "E", "E"}
    },
    ["Mordekaiser"] = {
        ["mostUsed"] = {"Q", "E", "W", "Q", "Q", "R", "Q", "E", "Q", "E", "R", "E", "E", "W", "W", "R", "W", "W"},
        ["highestRate"] = {"E", "Q", "W", "Q", "Q", "R", "Q", "E", "Q", "E", "R", "E", "E", "W", "W", "R", "W", "W"}
    },
    ["Morgana"] = {
        ["mostUsed"] = {"W", "Q", "W", "E", "W", "R", "W", "Q", "W", "Q", "R", "Q", "Q", "E", "E", "R", "E", "E"},
        ["highestRate"] = {"Q", "W", "E", "Q", "Q", "R", "Q", "E", "Q", "E", "R", "E", "E", "W", "W", "R", "W", "W"}
    },
    ["Nami"] = {
        ["mostUsed"] = {"W", "E", "Q", "W", "W", "R", "W", "E", "W", "E", "R", "E", "E", "Q", "Q", "R", "Q", "Q"},
        ["highestRate"] = {"W", "E", "Q", "W", "W", "R", "W", "E", "E", "W", "R", "E", "E", "Q", "Q", "R", "Q", "Q"}
    },
    ["Nasus"] = {
        ["mostUsed"] = {"Q", "E", "W", "Q", "Q", "R", "Q", "E", "Q", "E", "R", "E", "E", "W", "W", "R", "W", "W"},
        ["highestRate"] = {"E", "Q", "W", "Q", "Q", "R", "Q", "W", "Q", "W", "R", "W", "W", "E", "E", "R", "E", "E"}
    },
    ["Nautilus"] = {
        ["mostUsed"] = {"Q", "W", "E", "Q", "Q", "R", "Q", "W", "Q", "W", "R", "W", "W", "E", "E", "R", "E", "E"},
        ["highestRate"] = {"Q", "W", "E", "W", "W", "R", "W", "Q", "W", "Q", "R", "Q", "Q", "E", "E", "R", "E", "E"}
    },
    ["Neeko"] = {
        ["mostUsed"] = {"Q", "E", "W", "Q", "Q", "R", "Q", "E", "Q", "E", "R", "E", "E", "W", "W", "R", "W", "W"},
        ["highestRate"] = {"E", "W", "Q", "Q", "Q", "R", "Q", "E", "Q", "E", "R", "E", "E", "W", "W", "R", "W", "W"}
    },
    ["Nidalee"] = {
        ["mostUsed"] = {"Q", "W", "E", "Q", "Q", "R", "Q", "E", "Q", "E", "R", "E", "E", "W", "W", "R", "W", "W"},
        ["highestRate"] = {"Q", "W", "E", "Q", "Q", "R", "Q", "E", "Q", "E", "R", "E", "W", "E", "W", "R", "W", "W"}
    },
    ["Nilah"] = {
        ["mostUsed"] = {"Q", "E", "W", "Q", "Q", "R", "Q", "E", "Q", "E", "R", "E", "E", "W", "W", "R", "W", "W"},
        ["highestRate"] = {"Q", "E", "W", "Q", "Q", "R", "Q", "E", "Q", "E", "R", "E", "E", "W", "W", "R", "W", "W"}
    },
    ["Nocturne"] = {
        ["mostUsed"] = {"Q", "W", "E", "Q", "Q", "R", "Q", "E", "Q", "E", "R", "E", "E", "W", "W", "R", "W", "W"},
        ["highestRate"] = {"Q", "W", "Q", "E", "Q", "R", "Q", "E", "Q", "E", "R", "E", "E", "W", "W", "R", "W", "W"}
    },
    ["Nunu"] = {
        ["mostUsed"] = {"Q", "W", "E", "Q", "Q", "R", "Q", "E", "Q", "E", "R", "E", "E", "W", "W", "R", "W", "W"},
        ["highestRate"] = {"Q", "E", "W", "Q", "Q", "R", "Q", "W", "Q", "W", "R", "W", "W", "E", "E", "R", "E", "E"}
    },
    ["Olaf"] = {
        ["mostUsed"] = {"Q", "W", "E", "Q", "Q", "R", "Q", "E", "Q", "E", "R", "E", "E", "W", "W", "R", "W", "W"},
        ["highestRate"] = {"Q", "W", "Q", "E", "Q", "R", "Q", "W", "Q", "W", "R", "W", "W", "E", "E", "R", "E", "E"}
    },
    ["Orianna"] = {
        ["mostUsed"] = {"Q", "W", "E", "Q", "Q", "R", "Q", "W", "Q", "W", "R", "W", "W", "E", "E", "R", "E", "E"},
        ["highestRate"] = {"Q", "W", "E", "Q", "Q", "R", "Q", "W", "Q", "W", "R", "E", "W", "W", "E", "R", "E", "E"}
    },
    ["Ornn"] = {
        ["mostUsed"] = {"Q", "W", "E", "W", "W", "R", "W", "Q", "W", "Q", "R", "Q", "Q", "E", "E", "R", "E", "E"},
        ["highestRate"] = {"W", "Q", "E", "W", "W", "R", "W", "E", "W", "E", "R", "E", "E", "Q", "Q", "R", "Q", "Q"}
    },
    ["Pantheon"] = {
        ["mostUsed"] = {"Q", "W", "E", "Q", "Q", "R", "Q", "E", "Q", "E", "R", "E", "E", "W", "W", "R", "W", "W"},
        ["highestRate"] = {"Q", "W", "E", "Q", "Q", "R", "Q", "W", "Q", "E", "R", "E", "E", "E", "W", "R", "W", "W"}
    },
    ["Poppy"] = {
        ["mostUsed"] = {"Q", "E", "W", "Q", "Q", "R", "Q", "E", "Q", "E", "R", "E", "E", "W", "W", "R", "W", "W"},
        ["highestRate"] = {"E", "Q", "W", "Q", "Q", "R", "Q", "E", "Q", "E", "R", "E", "E", "W", "W", "R", "W", "W"}
    },
    ["Pyke"] = {
        ["mostUsed"] = {"Q", "E", "W", "Q", "Q", "R", "Q", "E", "Q", "E", "R", "E", "E", "W", "W", "R", "W", "W"},
        ["highestRate"] = {"Q", "E", "W", "Q", "Q", "R", "Q", "E", "Q", "E", "R", "E", "W", "E", "W", "R", "W", "W"}
    },
    ["Qiyana"] = {
        ["mostUsed"] = {"W", "Q", "E", "Q", "Q", "R", "Q", "W", "Q", "W", "R", "W", "W", "E", "E", "R", "E", "E"},
        ["highestRate"] = {"W", "Q", "E", "Q", "Q", "R", "Q", "W", "Q", "W", "R", "E", "W", "W", "E", "R", "E", "E"}
    },
    ["Quinn"] = {
        ["mostUsed"] = {"E", "Q", "W", "W", "W", "R", "W", "Q", "W", "Q", "R", "Q", "Q", "E", "E", "R", "E", "E"},
        ["highestRate"] = {"E", "W", "Q", "W", "W", "R", "W", "Q", "W", "Q", "R", "Q", "Q", "E", "E", "R", "E", "E"}
    },
    ["Rakan"] = {
        ["mostUsed"] = {"W", "E", "Q", "W", "W", "R", "W", "E", "W", "E", "R", "E", "E", "Q", "Q", "R", "Q", "Q"},
        ["highestRate"] = {"W", "E", "Q", "Q", "Q", "R", "Q", "E", "Q", "E", "R", "E", "E", "W", "W", "R", "W", "W"}
    },
    ["Rammus"] = {
        ["mostUsed"] = {"W", "Q", "E", "Q", "Q", "R", "Q", "E", "Q", "E", "R", "E", "E", "W", "W", "R", "W", "W"},
        ["highestRate"] = {"W", "E", "Q", "Q", "Q", "R", "Q", "E", "Q", "E", "R", "E", "E", "W", "W", "R", "W", "W"}
    },
    ["RekSai"] = {
        ["mostUsed"] = {"Q", "W", "E", "Q", "Q", "R", "Q", "E", "Q", "E", "R", "E", "E", "W", "W", "R", "W", "W"},
        ["highestRate"] = {"Q", "W", "E", "Q", "Q", "R", "Q", "E", "E", "E", "R", "E", "Q", "W", "W", "R", "W", "W"}
    },
    ["Rell"] = {
        ["mostUsed"] = {"W", "E", "Q", "W", "W", "R", "W", "E", "W", "E", "R", "E", "E", "Q", "Q", "R", "Q", "Q"},
        ["highestRate"] = {"W", "E", "Q", "Q", "Q", "R", "Q", "E", "Q", "E", "R", "E", "E", "W", "W", "R", "W", "W"}
    },
    ["Renata"] = {
        ["mostUsed"] = {"E", "Q", "W", "E", "E", "R", "E", "W", "E", "W", "R", "W", "W", "Q", "Q", "R", "Q", "Q"},
        ["highestRate"] = {"E", "Q", "W", "E", "E", "R", "E", "W", "E", "W", "R", "W", "W", "Q", "Q", "R", "Q", "Q"}
    },
    ["Renekton"] = {
        ["mostUsed"] = {"Q", "E", "W", "Q", "Q", "R", "Q", "E", "Q", "E", "R", "E", "E", "W", "W", "R", "W", "W"},
        ["highestRate"] = {"W", "E", "Q", "Q", "Q", "R", "Q", "E", "Q", "E", "R", "E", "E", "W", "W", "R", "W", "W"}
    },
    ["Rengar"] = {
        ["mostUsed"] = {"Q", "W", "E", "Q", "Q", "R", "Q", "E", "Q", "E", "R", "E", "E", "W", "W", "R", "W", "W"},
        ["highestRate"] = {"Q", "W", "E", "Q", "Q", "R", "Q", "W", "Q", "E", "R", "W", "W", "W", "E", "R", "E", "E"}
    },
    ["Riven"] = {
        ["mostUsed"] = {"Q", "E", "W", "Q", "Q", "R", "Q", "E", "Q", "E", "R", "E", "E", "W", "W", "R", "W", "W"},
        ["highestRate"] = {"Q", "E", "W", "Q", "Q", "R", "Q", "E", "Q", "E", "R", "E", "W", "E", "W", "R", "W", "W"}
    },
    ["Rumble"] = {
        ["mostUsed"] = {"Q", "E", "W", "Q", "Q", "R", "Q", "E", "Q", "E", "R", "E", "E", "W", "W", "R", "W", "W"},
        ["highestRate"] = {"W", "Q", "Q", "E", "Q", "R", "Q", "E", "Q", "E", "R", "E", "E", "W", "W", "R", "W", "W"}
    },
    ["Ryze"] = {
        ["mostUsed"] = {"W", "E", "Q", "Q", "Q", "R", "Q", "E", "Q", "E", "R", "E", "E", "W", "W", "R", "W", "W"},
        ["highestRate"] = {"E", "W", "Q", "Q", "Q", "R", "Q", "E", "Q", "E", "R", "E", "E", "W", "W", "R", "W", "W"}
    },
    ["Samira"] = {
        ["mostUsed"] = {"Q", "E", "W", "Q", "Q", "R", "Q", "E", "Q", "E", "R", "E", "E", "W", "W", "R", "W", "W"},
        ["highestRate"] = {"E", "Q", "W", "Q", "Q", "R", "Q", "E", "Q", "E", "R", "E", "E", "W", "W", "R", "W", "W"}
    },
    ["Sejuani"] = {
        ["mostUsed"] = {"E", "W", "Q", "W", "W", "R", "W", "Q", "W", "Q", "R", "Q", "Q", "E", "E", "R", "E", "E"},
        ["highestRate"] = {"E", "W", "Q", "W", "W", "R", "W", "E", "W", "Q", "R", "Q", "Q", "Q", "E", "R", "E", "E"}
    },
    ["Senna"] = {
        ["mostUsed"] = {"Q", "W", "E", "Q", "Q", "R", "Q", "W", "Q", "W", "R", "W", "W", "E", "E", "R", "E", "E"},
        ["highestRate"] = {"Q", "W", "Q", "E", "Q", "R", "Q", "W", "Q", "W", "R", "W", "W", "E", "E", "R", "E", "E"}
    },
    ["Seraphine"] = {
        ["mostUsed"] = {"Q", "E", "W", "Q", "Q", "R", "Q", "E", "Q", "E", "R", "E", "E", "W", "W", "R", "W", "W"},
        ["highestRate"] = {"Q", "W", "E", "Q", "Q", "R", "Q", "E", "Q", "E", "R", "E", "E", "W", "W", "R", "W", "W"}
    },
    ["Sett"] = {
        ["mostUsed"] = {"E", "Q", "W", "Q", "Q", "R", "Q", "W", "Q", "W", "R", "W", "W", "E", "E", "R", "E", "E"},
        ["highestRate"] = {"W", "E", "Q", "Q", "Q", "R", "Q", "W", "Q", "W", "R", "W", "W", "E", "E", "R", "E", "E"}
    },
    ["Shaco"] = {
        ["mostUsed"] = {"W", "Q", "E", "E", "E", "R", "E", "Q", "E", "Q", "R", "Q", "Q", "W", "W", "R", "W", "W"},
        ["highestRate"] = {"W", "Q", "E", "W", "W", "R", "E", "E", "E", "E", "R", "Q", "Q", "Q", "Q", "R", "W", "W"}
    },
    ["Shen"] = {
        ["mostUsed"] = {"Q", "E", "W", "Q", "Q", "R", "Q", "E", "Q", "E", "R", "E", "E", "W", "W", "R", "W", "W"},
        ["highestRate"] = {"E", "Q", "W", "E", "E", "R", "E", "Q", "E", "Q", "R", "Q", "Q", "W", "W", "R", "W", "W"}
    },
    ["Shyvana"] = {
        ["mostUsed"] = {"E", "W", "Q", "E", "E", "R", "E", "W", "E", "W", "R", "W", "W", "Q", "Q", "R", "Q", "Q"},
        ["highestRate"] = {"E", "W", "Q", "W", "W", "R", "W", "E", "W", "E", "R", "E", "E", "Q", "Q", "R", "Q", "Q"}
    },
    ["Singed"] = {
        ["mostUsed"] = {"Q", "E", "W", "Q", "Q", "R", "Q", "E", "Q", "E", "R", "E", "E", "W", "W", "R", "W", "W"},
        ["highestRate"] = {"Q", "E", "Q", "W", "Q", "R", "Q", "E", "E", "Q", "R", "E", "E", "W", "W", "R", "W", "W"}
    },
    ["Sion"] = {
        ["mostUsed"] = {"Q", "W", "E", "Q", "Q", "R", "Q", "W", "Q", "W", "R", "W", "W", "E", "E", "R", "E", "E"},
        ["highestRate"] = {"Q", "E", "W", "Q", "Q", "R", "Q", "E", "Q", "E", "R", "E", "E", "W", "W", "R", "W", "W"}
    },
    ["Sivir"] = {
        ["mostUsed"] = {"Q", "E", "W", "Q", "Q", "R", "Q", "W", "Q", "W", "R", "W", "W", "E", "E", "R", "E", "E"},
        ["highestRate"] = {"Q", "W", "E", "Q", "Q", "R", "Q", "E", "Q", "E", "R", "E", "E", "W", "W", "R", "W", "W"}
    },
    ["Skarner"] = {
        ["mostUsed"] = {"Q", "E", "W", "Q", "Q", "R", "Q", "W", "Q", "W", "R", "W", "W", "E", "E", "R", "E", "E"},
        ["highestRate"] = {"Q", "E", "W", "Q", "Q", "R", "Q", "W", "Q", "W", "R", "W", "W", "E", "E", "R", "E", "E"}
    },
    ["Sona"] = {
        ["mostUsed"] = {"Q", "W", "E", "Q", "Q", "R", "Q", "W", "Q", "W", "R", "W", "W", "E", "E", "R", "E", "E"},
        ["highestRate"] = {"Q", "W", "E", "W", "W", "R", "W", "E", "W", "E", "R", "E", "E", "Q", "Q", "R", "Q", "Q"}
    },
    ["Soraka"] = {
        ["mostUsed"] = {"Q", "W", "E", "W", "W", "R", "W", "Q", "W", "Q", "R", "Q", "Q", "E", "E", "R", "E", "E"},
        ["highestRate"] = {"Q", "E", "W", "Q", "Q", "R", "W", "W", "W", "W", "R", "Q", "Q", "E", "E", "R", "E", "E"}
    },
    ["Swain"] = {
        ["mostUsed"] = {"E", "W", "Q", "Q", "Q", "R", "Q", "W", "Q", "W", "R", "W", "W", "E", "E", "R", "E", "E"},
        ["highestRate"] = {"E", "Q", "W", "E", "E", "R", "E", "Q", "E", "Q", "R", "Q", "Q", "W", "W", "R", "W", "W"}
    },
    ["Sylas"] = {
        ["mostUsed"] = {"E", "W", "Q", "W", "W", "R", "W", "Q", "W", "Q", "R", "Q", "Q", "E", "E", "R", "E", "E"},
        ["highestRate"] = {"E", "W", "Q", "W", "W", "R", "W", "Q", "W", "Q", "R", "Q", "Q", "E", "E", "R", "E", "E"}
    },
    ["Syndra"] = {
        ["mostUsed"] = {"Q", "E", "W", "Q", "Q", "R", "Q", "E", "Q", "E", "R", "E", "E", "W", "W", "R", "W", "W"},
        ["highestRate"] = {"Q", "E", "Q", "W", "Q", "R", "Q", "E", "Q", "E", "R", "E", "E", "W", "W", "R", "W", "W"}
    },
    ["TahmKench"] = {
        ["mostUsed"] = {"Q", "W", "E", "Q", "Q", "R", "Q", "W", "Q", "W", "R", "W", "W", "E", "E", "R", "E", "E"},
        ["highestRate"] = {"Q", "W", "Q", "E", "Q", "R", "Q", "W", "Q", "W", "R", "W", "W", "E", "E", "R", "E", "E"}
    },
    ["Taliyah"] = {
        ["mostUsed"] = {"Q", "E", "W", "Q", "Q", "R", "Q", "E", "Q", "E", "R", "E", "E", "W", "W", "R", "W", "W"},
        ["highestRate"] = {"Q", "W", "E", "Q", "Q", "R", "Q", "E", "Q", "E", "R", "E", "W", "E", "W", "R", "W", "W"}
    },
    ["Talon"] = {
        ["mostUsed"] = {"W", "Q", "E", "W", "W", "R", "W", "Q", "W", "Q", "R", "Q", "Q", "E", "E", "R", "E", "E"},
        ["highestRate"] = {"Q", "W", "E", "W", "W", "R", "W", "Q", "W", "Q", "R", "Q", "Q", "E", "E", "R", "E", "E"}
    },
    ["Taric"] = {
        ["mostUsed"] = {"E", "W", "Q", "E", "E", "R", "E", "Q", "E", "Q", "R", "Q", "Q", "W", "W", "R", "W", "W"},
        ["highestRate"] = {"E", "W", "Q", "E", "E", "R", "E", "W", "E", "W", "R", "W", "W", "Q", "Q", "R", "Q", "Q"}
    },
    ["Teemo"] = {
        ["mostUsed"] = {"E", "Q", "W", "E", "E", "R", "E", "Q", "E", "Q", "R", "Q", "Q", "W", "W", "R", "W", "W"},
        ["highestRate"] = {"E", "Q", "E", "W", "E", "R", "E", "W", "E", "W", "R", "W", "W", "Q", "Q", "R", "Q", "Q"}
    },
    ["Thresh"] = {
        ["mostUsed"] = {"Q", "E", "W", "Q", "Q", "R", "Q", "E", "Q", "E", "R", "E", "E", "W", "W", "R", "W", "W"},
        ["highestRate"] = {"E", "Q", "W", "W", "W", "R", "W", "Q", "W", "Q", "R", "Q", "Q", "E", "E", "R", "E", "E"}
    },
    ["Tristana"] = {
        ["mostUsed"] = {"E", "W", "Q", "E", "E", "R", "E", "Q", "E", "Q", "R", "Q", "Q", "W", "W", "R", "W", "W"},
        ["highestRate"] = {"E", "W", "Q", "E", "E", "R", "E", "Q", "E", "Q", "R", "Q", "W", "Q", "W", "R", "W", "W"}
    },
    ["Trundle"] = {
        ["mostUsed"] = {"Q", "W", "E", "Q", "Q", "R", "Q", "W", "Q", "W", "R", "W", "W", "E", "E", "R", "E", "E"},
        ["highestRate"] = {"E", "Q", "W", "Q", "Q", "R", "Q", "W", "Q", "W", "R", "W", "W", "E", "E", "R", "E", "E"}
    },
    ["Tryndamere"] = {
        ["mostUsed"] = {"E", "Q", "W", "Q", "Q", "R", "Q", "E", "Q", "E", "R", "E", "E", "W", "W", "R", "W", "W"},
        ["highestRate"] = {"E", "Q", "Q", "W", "Q", "R", "Q", "E", "Q", "E", "E", "E", "W", "W", "W", "W", "R", "R"}
    },
    ["TwistedFate"] = {
        ["mostUsed"] = {"E", "W", "Q", "Q", "Q", "R", "Q", "W", "Q", "W", "R", "W", "W", "E", "E", "R", "E", "E"},
        ["highestRate"] = {"E", "W", "E", "W", "E", "R", "E", "W", "E", "W", "R", "W", "Q", "Q", "Q", "R", "Q", "Q"}
    },
    ["Twitch"] = {
        ["mostUsed"] = {"E", "W", "Q", "E", "E", "R", "E", "Q", "E", "Q", "R", "Q", "Q", "W", "W", "R", "W", "W"},
        ["highestRate"] = {"Q", "W", "E", "E", "E", "R", "E", "Q", "E", "Q", "R", "Q", "Q", "W", "W", "R", "W", "W"}
    },
    ["Udyr"] = {
        ["mostUsed"] = {"Q", "R", "R", "E", "R", "W", "R", "E", "R", "E", "E", "E", "W", "W", "W", "R", "E", "W"},
        ["highestRate"] = {"Q", "W", "E", "Q", "Q", "E", "Q", "E", "Q", "E", "E", "W", "W", "W", "W", "Q", "E", "W"}
    },
    ["Urgot"] = {
        ["mostUsed"] = {"E", "W", "Q", "W", "W", "R", "W", "E", "W", "E", "R", "E", "E", "Q", "Q", "R", "Q", "Q"},
        ["highestRate"] = {"E", "W", "Q", "Q", "W", "R", "W", "W", "W", "Q", "R", "Q", "Q", "E", "E", "R", "E", "E"}
    },
    ["Varus"] = {
        ["mostUsed"] = {"E", "Q", "W", "Q", "Q", "R", "Q", "E", "Q", "E", "R", "E", "E", "W", "W", "R", "W", "W"},
        ["highestRate"] = {"E", "W", "Q", "Q", "Q", "R", "Q", "E", "Q", "E", "R", "E", "E", "W", "W", "R", "W", "W"}
    },
    ["Vayne"] = {
        ["mostUsed"] = {"Q", "W", "E", "W", "W", "R", "W", "Q", "W", "Q", "R", "Q", "Q", "E", "E", "R", "E", "E"},
        ["highestRate"] = {"Q", "W", "E", "Q", "Q", "R", "W", "W", "W", "W", "R", "Q", "Q", "E", "E", "R", "E", "E"}
    },
    ["Veigar"] = {
        ["mostUsed"] = {"Q", "W", "E", "Q", "Q", "R", "Q", "W", "Q", "W", "R", "W", "W", "E", "E", "R", "E", "E"},
        ["highestRate"] = {"Q", "W", "E", "Q", "Q", "R", "Q", "W", "Q", "E", "R", "E", "E", "E", "W", "R", "W", "W"}
    },
    ["Velkoz"] = {
        ["mostUsed"] = {"Q", "W", "E", "Q", "Q", "R", "Q", "W", "Q", "W", "R", "W", "W", "E", "E", "R", "E", "E"},
        ["highestRate"] = {"Q", "E", "W", "Q", "Q", "R", "Q", "W", "Q", "W", "R", "W", "W", "E", "E", "R", "E", "E"}
    },
    ["Vi"] = {
        ["mostUsed"] = {"W", "E", "Q", "Q", "Q", "R", "Q", "E", "Q", "E", "R", "E", "E", "W", "W", "R", "W", "W"},
        ["highestRate"] = {"W", "Q", "E", "Q", "Q", "R", "Q", "E", "Q", "E", "R", "E", "E", "W", "W", "R", "W", "W"}
    },
    ["Viego"] = {
        ["mostUsed"] = {"Q", "W", "E", "Q", "Q", "R", "Q", "E", "Q", "E", "R", "E", "E", "W", "W", "R", "W", "W"},
        ["highestRate"] = {"Q", "W", "Q", "E", "Q", "R", "Q", "E", "Q", "E", "R", "E", "E", "W", "W", "R", "W", "W"}
    },
    ["Viktor"] = {
        ["mostUsed"] = {"Q", "E", "E", "W", "E", "R", "E", "Q", "E", "Q", "R", "Q", "Q", "W", "W", "R", "W", "W"},
        ["highestRate"] = {"Q", "E", "Q", "W", "E", "R", "E", "E", "E", "Q", "R", "Q", "Q", "W", "W", "R", "W", "W"}
    },
    ["Vladimir"] = {
        ["mostUsed"] = {"Q", "E", "W", "Q", "Q", "R", "Q", "E", "Q", "E", "R", "E", "E", "W", "W", "R", "W", "W"},
        ["highestRate"] = {"Q", "E", "W", "Q", "Q", "R", "Q", "E", "E", "Q", "R", "E", "E", "W", "W", "R", "W", "W"}
    },
    ["Volibear"] = {
        ["mostUsed"] = {"W", "E", "Q", "W", "W", "R", "W", "Q", "W", "Q", "R", "Q", "Q", "E", "E", "R", "E", "E"},
        ["highestRate"] = {"Q", "E", "W", "W", "W", "R", "W", "Q", "W", "Q", "R", "Q", "Q", "E", "E", "R", "E", "E"}
    },
    ["Warwick"] = {
        ["mostUsed"] = {"Q", "W", "E", "Q", "Q", "R", "Q", "W", "Q", "W", "R", "W", "W", "E", "E", "R", "E", "E"},
        ["highestRate"] = {"Q", "W", "E", "W", "W", "R", "W", "Q", "W", "Q", "R", "Q", "Q", "E", "E", "R", "E", "E"}
    },
    ["MonkeyKing"] = {
        ["mostUsed"] = {"E", "Q", "W", "Q", "Q", "R", "Q", "E", "Q", "E", "R", "E", "E", "W", "W", "R", "W", "W"},
        ["highestRate"] = {"E", "W", "Q", "E", "E", "R", "E", "Q", "E", "Q", "R", "Q", "Q", "W", "W", "R", "W", "W"}
    },
    ["Xayah"] = {
        ["mostUsed"] = {"Q", "E", "W", "E", "E", "R", "E", "W", "E", "W", "R", "W", "W", "Q", "Q", "R", "Q", "Q"},
        ["highestRate"] = {"W", "Q", "E", "E", "E", "R", "E", "W", "E", "W", "R", "W", "W", "Q", "Q", "R", "Q", "Q"}
    },
    ["Xerath"] = {
        ["mostUsed"] = {"Q", "W", "E", "Q", "Q", "R", "Q", "W", "Q", "W", "R", "W", "W", "E", "E", "R", "E", "E"},
        ["highestRate"] = {"W", "E", "Q", "Q", "Q", "R", "Q", "W", "Q", "W", "R", "W", "W", "E", "E", "R", "E", "E"}
    },
    ["XinZhao"] = {
        ["mostUsed"] = {"E", "Q", "W", "W", "W", "R", "W", "E", "W", "E", "R", "E", "E", "Q", "Q", "R", "Q", "Q"},
        ["highestRate"] = {"E", "W", "Q", "W", "W", "R", "W", "Q", "W", "Q", "R", "Q", "Q", "E", "E", "R", "E", "E"}
    },
    ["Yasuo"] = {
        ["mostUsed"] = {"Q", "E", "W", "Q", "Q", "R", "Q", "E", "Q", "E", "R", "E", "E", "W", "W", "R", "W", "W"},
        ["highestRate"] = {"Q", "E", "W", "Q", "Q", "R", "Q", "E", "E", "Q", "R", "E", "E", "W", "W", "R", "W", "W"}
    },
    ["Yone"] = {
        ["mostUsed"] = {"Q", "W", "E", "Q", "Q", "R", "Q", "E", "Q", "E", "R", "E", "E", "W", "W", "R", "W", "W"},
        ["highestRate"] = {"Q", "W", "E", "Q", "Q", "R", "Q", "E", "Q", "E", "R", "W", "E", "E", "W", "R", "W", "W"}
    },
    ["Yorick"] = {
        ["mostUsed"] = {"Q", "E", "W", "Q", "Q", "R", "Q", "E", "Q", "E", "R", "E", "E", "W", "W", "R", "W", "W"},
        ["highestRate"] = {"Q", "E", "W", "Q", "Q", "R", "Q", "E", "Q", "E", "R", "E", "W", "E", "W", "R", "W", "W"}
    },
    ["Yuumi"] = {
        ["mostUsed"] = {"Q", "E", "E", "W", "E", "R", "E", "W", "E", "W", "R", "W", "Q", "Q", "Q", "R", "Q", "W"},
        ["highestRate"] = {"E", "Q", "E", "W", "E", "R", "E", "W", "E", "W", "R", "W", "Q", "Q", "Q", "R", "Q", "Q"}
    },
    ["Zac"] = {
        ["mostUsed"] = {"W", "Q", "E", "E", "E", "R", "E", "W", "E", "W", "R", "W", "W", "Q", "Q", "R", "Q", "Q"},
        ["highestRate"] = {"E", "Q", "W", "E", "E", "R", "E", "W", "E", "W", "R", "W", "W", "Q", "Q", "R", "Q", "Q"}
    },
    ["Zed"] = {
        ["mostUsed"] = {"Q", "E", "W", "Q", "Q", "R", "Q", "E", "Q", "E", "R", "E", "E", "W", "W", "R", "W", "W"},
        ["highestRate"] = {"Q", "E", "W", "Q", "Q", "R", "Q", "E", "E", "Q", "R", "E", "E", "W", "W", "R", "W", "W"}
    },
    ["Zeri"] = {
        ["mostUsed"] = {"Q", "E", "W", "Q", "Q", "R", "Q", "E", "Q", "E", "R", "E", "E", "W", "W", "R", "W", "W"},
        ["highestRate"] = {"Q", "E", "W", "Q", "Q", "R", "Q", "E", "Q", "E", "R", "E", "E", "W", "W", "R", "W", "W"}
    },
    ["Ziggs"] = {
        ["mostUsed"] = {"Q", "E", "W", "Q", "Q", "R", "Q", "E", "Q", "E", "R", "E", "E", "W", "W", "R", "W", "W"},
        ["highestRate"] = {"Q", "E", "W", "Q", "Q", "R", "Q", "E", "Q", "E", "R", "W", "E", "E", "W", "R", "W", "W"}
    },
    ["Zilean"] = {
        ["mostUsed"] = {"Q", "W", "E", "Q", "Q", "R", "Q", "E", "Q", "E", "R", "E", "E", "W", "W", "R", "W", "W"},
        ["highestRate"] = {"Q", "W", "E", "E", "E", "R", "E", "Q", "E", "Q", "R", "Q", "Q", "W", "W", "R", "W", "W"}
    },
    ["Zoe"] = {
        ["mostUsed"] = {"Q", "E", "W", "Q", "Q", "R", "Q", "E", "Q", "E", "R", "E", "E", "W", "W", "R", "W", "W"},
        ["highestRate"] = {"Q", "E", "W", "Q", "Q", "R", "Q", "W", "Q", "W", "R", "W", "W", "E", "E", "R", "E", "E"}
    },
    ["Zyra"] = {
        ["mostUsed"] = {"Q", "E", "W", "Q", "Q", "R", "Q", "E", "Q", "E", "R", "E", "E", "W", "W", "R", "W", "W"},
        ["highestRate"] = {"Q", "E", "W", "E", "E", "R", "E", "Q", "E", "Q", "R", "Q", "Q", "W", "W", "R", "W", "W"}
    },
    ["Vex"] = {
        ["mostUsed"] = {"E", "Q", "W", "Q", "Q", "R", "Q", "W", "Q", "W", "R", "W", "W", "E", "E", "R", "E", "E"},
        ["highestRate"] = {"E", "Q", "W", "Q", "Q", "R", "Q", "W", "Q", "W", "R", "W", "W", "E", "E", "R", "E", "E"}
    },
}

local BigJungleMonsters = {
    SRU_Baron = true,
    SRU_RiftHerald = true,
    SRU_Dragon_Air = true,
    SRU_Dragon_Fire = true,
    SRU_Dragon_Earth = true,
    SRU_Dragon_Water = true,
    SRU_Dragon_Chemtech = true,
    SRU_Dragon_Hextech = true,
    SRU_Dragon_Elder = true,
    SRU_Blue = true,
    SRU_Red = true,
    SRU_Gromp = true,
    SRU_Murkwolf = true,
    SRU_Razorbeak = true,
    SRU_Krug = true,
    Sru_Crab = true,
}

local JungleMonsters = {
    { Name = "SRU_Baron",        DisplayName = "Baron Nashor",   Enabled = true },
    { Name = "SRU_RiftHerald",   DisplayName = "Rift Herald",    Enabled = true },
    { Name = "SRU_Dragon_Air",   DisplayName = "Cloud Drake",    Enabled = true },
    { Name = "SRU_Dragon_Fire",  DisplayName = "Infernal Drake", Enabled = true },
    { Name = "SRU_Dragon_Earth", DisplayName = "Mountain Drake", Enabled = true },
    { Name = "SRU_Dragon_Water", DisplayName = "Ocean Drake",    Enabled = true },
    { Name = "SRU_Dragon_Chemtech", DisplayName = "Chemtech Drake", Enabled = true },
    { Name = "SRU_Dragon_Hextech", DisplayName = "Hextech Drake",    Enabled = true },
    { Name = "SRU_Dragon_Elder", DisplayName = "Elder Drake",    Enabled = true },
    { Name = "SRU_Blue",         DisplayName = "Blue Buff",      Enabled = true },
    { Name = "SRU_Red",          DisplayName = "Red Buff",       Enabled = true },
    { Name = "SRU_Gromp",        DisplayName = "Gromp",          Enabled = false },
    { Name = "SRU_Murkwolf",     DisplayName = "Greater Wolf",   Enabled = false },
    { Name = "SRU_Razorbeak",    DisplayName = "Crimson Raptor", Enabled = false },
    { Name = "SRU_Krug",         DisplayName = "Ancient Krug",   Enabled = false },
    { Name = "Sru_Crab",         DisplayName = "Rift Scuttler",  Enabled = false },
}

local TargetSpells = {
    ["Alistar"] = {
        ["Headbutt"] = {
            ["OnBuffGain"] = "headbutttarget",
        }
    },
    ["Brand"] = {
        ["BrandE"] = {
            ["OnBuffGain"] = "BrandAblaze",
            ["Delay"] = 0.25,
        },
    },
    ["Chogath"] = {
        ["Feast"] = {
            ["OnBuffGain"] = nil,
            ["Delay"] = 0.25,
        },
    },
    ["Darius"] = {
        ["DariusExecute"] = {
            ["OnBuffGain"] = nil,
            ["Delay"] = 0.3667,
        }
    },
    ["Diana"] = {
        ["DianaTeleport"] = {
            ["OnBuffGain"] = nil,
            ["Delay"] = 0.25,
        }
    },
    ["Ekko"] = {
        ["EkkoEAttack"] = {
            ["OnBuffGain"] = nil,
            ["Delay"] = 0.25,
        }
    },
    ["Elise"] = {
        ["EliseSpiderQCast"] = {
            ["OnBuffGain"] = nil,
            ["Delay"] = 0.25,
        }
    },
    ["Evelynn"] = {
        ["EvelynnQ2"] = {
            ["OnBuffGain"] = nil,
            ["Delay"] = 0.25,
        },
        ["EvelynnE"] = {
            ["OnBuffGain"] = nil,
            ["Delay"] = 0.25,
        },
        ["EvelynnE2"] = {
            ["OnBuffGain"] = nil,
            ["Delay"] = 0.25,
        },
    },
    ["Fizz"] = {
        ["FizzQ"] = {
            ["OnBuffGain"] = nil,
            ["Delay"] = 0.25,
        }
    },
    ["Irelia"] = {
        ["IreliaQ"] = {
            ["OnBuffGain"] = nil,
            ["Delay"] = 0.25,
        }
    },
    ['Jax'] = {
        ['JaxLeapStrike'] = {
            ['OnBuffGain'] = nil,
            ['Delay'] = 0.25
        },
    },
    ['Kayle'] = {
        ['KayleE'] = {
            ['OnBuffGain'] = nil,
            ['Delay'] = 0.25
        },
    },
    ['LeeSin'] = {
        ['BlindMonkRKick'] = {
            ['OnBuffGain'] = nil,
            ['Delay'] = 0.25
        },
    },
    ['Lissandra'] = {
        ['LissandraR'] = {
            ['OnBuffGain'] = nil,
            ['Delay'] = 0.25
        },
    },
    ['Nunu'] = {
        ['NunuQ'] = {
            ['OnBuffGain'] = nil,
            ['Delay'] = 0.25
        },
    },
    ['Olaf'] = {
        ['OlafRecklessStrike'] = {
            ['OnBuffGain'] = nil,
            ['Delay'] = 0.25
        },
    },
    ['Pantheon'] = {
        ['PantheonW'] = {
            ['OnBuffGain'] = nil,
            ['Delay'] = 0.25
        },
    },
    ['Poppy'] = {
        ['PoppyE'] = {
            ['OnBuffGain'] = nil,
            ['Delay'] = 0.25
        },
    },
    ['Ryze'] = {
        ['RyzeW'] = {
            ['OnBuffGain'] = nil,
            ['Delay'] = 0.25
        },
        ['RyzeE'] = {
            ['OnBuffGain'] = nil,
            ['Delay'] = 0.25
        },
    },
    ['Singed'] = {
        ['Fling'] = {
            ['OnBuffGain'] = nil,
            ['Delay'] = 0.25
        },
    },
    ['Skarner'] = {
        ['SkarnerImpale'] = {
            ['OnBuffGain'] = nil,
            ['Delay'] = 0.25
        },
    },
    ['Tristana'] = {
        ['TristanaE'] = {
            ['OnBuffGain'] = nil,
            ['Delay'] = 0.25
        },
    },
    ['Warwick'] = {
        ['WarwickQ'] = {
            ['OnBuffGain'] = nil,
            ['Delay'] = 0.25
        },
    },
    ['JarvanIV'] = {
        ['JarvanIVCataclysm'] = {
            ['OnBuffGain'] = nil,
            ['Delay'] = 0.25
        },
    },
    ['Jayce'] = {
        ['JayceToTheSkies'] = {
            ['OnBuffGain'] = nil,
            ['Delay'] = 0.25
        },
        ['JayceThunderingBlow'] = {
            ['OnBuffGain'] = nil,
            ['Delay'] = 0.25
        },
    },
    ['Kayn'] = {
        ['KaynR'] = {
            ['OnBuffGain'] = nil,
            ['Delay'] = 0.25
        },
    },
    ['Khazix'] = {
        ['KhazixQ'] = {
            ['OnBuffGain'] = nil,
            ['Delay'] = 0.25
        },
        ['KhazixQLong'] = {
            ['OnBuffGain'] = nil,
            ['Delay'] = 0.25
        },
    },
    ['Maokai'] = {
        ['MaokaiW'] = {
            ['OnBuffGain'] = nil,
            ['Delay'] = 0.25
        },
    },
    ['MonkeyKing'] = {
        ['MonkeyKingNimbus'] = {
            ['OnBuffGain'] = nil,
            ['Delay'] = 0.25
        },
    },
    ['Nautilus'] = {
        ['NautilusGrandLine'] = {
            ['OnBuffGain'] = nil,
            ['Delay'] = 0.25
        },
    },
    ['Nocturne'] = {
        ['NocturneParanoia'] = {
            ['OnBuffGain'] = nil,
            ['Delay'] = 0.25
        },
        ['NocturneParanoia2'] = {
            ['OnBuffGain'] = nil,
            ['Delay'] = 0.25
        },
    },
    ['Qiyana'] = {
        ['QiyanaE'] = {
            ['OnBuffGain'] = nil,
            ['Delay'] = 0.25
        },
    },
    ['Quinn'] = {
        ['QuinnE'] = {
            ['OnBuffGain'] = nil,
            ['Delay'] = 0.25
        },
    },
    ['RekSai'] = {
        ['RekSaiE'] = {
            ['OnBuffGain'] = nil,
            ['Delay'] = 0.25
        },
        ['RekSaiRWrapper'] = {
            ['OnBuffGain'] = nil,
            ['Delay'] = 0.25
        },
    },
    ['Talon'] = {
        ['TalonQ'] = {
            ['OnBuffGain'] = nil,
            ['Delay'] = 0.25
        },
    },
    ['Trundle'] = {
        ['TrundlePain'] = {
            ['OnBuffGain'] = nil,
            ['Delay'] = 0.25
        },
    },
    ['Vi'] = {
        ['ViR'] = {
            ['OnBuffGain'] = nil,
            ['Delay'] = 0.25
        },
    },
    ['Vladimir'] = {
        ['VladimirQ'] = {
            ['OnBuffGain'] = nil,
            ['Delay'] = 0.25
        },
    },
    ['Volibear'] = {
        ['VolibearW'] = {
            ['OnBuffGain'] = nil,
            ['Delay'] = 0.25
        },
    },
    ['Yasuo'] = {
        ['YasuoE'] = {
            ['OnBuffGain'] = nil,
            ['Delay'] = 0.25
        },
    },
}

local SpellParticles = {
    ["Amumu_Base_W_Despair_buf"] = {
        ['CharName'] = "Amumu",
        ['Range'] = 300,
        ['FixedPosition'] = false,
        ['UpdatePosition'] = 0,
    },
    ["Diana_Base_R_Hit_1"] = {
        ['CharName'] = "Diana",
        ['Range'] = 475,
        ['FixedPosition'] = false,
        ['UpdatePosition'] = 0,
    },
    ["Diana_Base_R_Hit_2"] = {
        ['CharName'] = "Diana",
        ['Range'] = 475,
        ['FixedPosition'] = false,
        ['UpdatePosition'] = 0,
    },
    ["Diana_Base_R_Hit_3"] = {
        ['CharName'] = "Diana",
        ['Range'] = 475,
        ['FixedPosition'] = false,
        ['UpdatePosition'] = 0,
    },
    ["Diana_Base_R_Hit_4"] = {
        ['CharName'] = "Diana",
        ['Range'] = 475,
        ['FixedPosition'] = false,
        ['UpdatePosition'] = 0,
    },
    ["Diana_Base_R_Hit_5"] = {
        ['CharName'] = "Diana",
        ['Range'] = 475,
        ['FixedPosition'] = false,
        ['UpdatePosition'] = 0,
    },
    ["Elise_Base_W_volatile_cas"] = {
        ['CharName'] = "Elise",
        ['Range'] = 475,
        ['FixedPosition'] = false,
        ['UpdatePosition'] = 0,
    },
    ["Anivia_Base_R_indicator_ring"] = {
        ['CharName'] = "Anivia",
        ['Range'] = 400,
        ['FixedPosition'] = true,
        ['UpdatePosition'] = 0,
    },
    ["Corki_Base_W_tar"] = {
        ['CharName'] = "Corki",
        ['Range'] = 150,
        ['FixedPosition'] = true,
        ['UpdatePosition'] = 0,
    },
    ["Corki_Base_W_Loaded_tar"] = {
        ['CharName'] = "Corki",
        ['Range'] = 200,
        ['FixedPosition'] = true,
        ['UpdatePosition'] = 0,
    },
    ["FiddleSticks_Base_R_Tar"] = {
        ['CharName'] = "FiddleSticks",
        ['Range'] = 600,
        ['FixedPosition'] = false,
        ['UpdatePosition'] = 0,
    },
    ["Tibbers"] = {
        ['CharName'] = "Annie",
        ['Range'] = 300,
        ['FixedPosition'] = true,
        ['UpdatePosition'] = 1
    },
}

for handle, object in pairs(ObjectManager.Get("all", "heroes")) do
    local hero = object.AsHero
    Heroes[handle] = {
        --// Static Values //--
        ["Handle"] = handle,
        ["Object"] = hero,
        ["CharName"] = hero.CharName,
        ["IsAlly"] = hero.IsAlly,
        ["IsEnemy"] = hero.IsEnemy,
        ["IsMe"] = hero.IsMe,

        --// Dynamic Values //--
        ["Position"] = {
            Value = Vector(0, 0, 0),
            UpdateInterval = 0.25,
            LastUpdate = 0,
        },
        ["IsDead"] = {
            Value = false,
            UpdateInterval = 1,
            LastUpdate = 0,
        },
        ["IsVisible"] = {
            Value = false,
            UpdateInterval = 1,
            LastUpdate = 0,
        },
        ["IsOnScreen"] = {
            Value = false,
            UpdateInterval = 0,
            LastUpdate = 0,
        },
        ["HealthPercent"] = {
            Value = 0,
            UpdateInterval = 0.15,
            LastUpdate = 0,
        },
        ["IsTargetable"] = {
            Value = false,
            UpdateInterval = 0.25,
            LastUpdate = 0,
        }
    }

    Buffs[handle] = {}

    for slot = 4, 5 do
        local spell = hero:GetSpell(slot)
        if spell then
            for k, sumName in pairs({ "SummonerDot", "SummonerExhaust" }) do
                if spell.Name == sumName then
                    if not DebuffData[hero.CharName] then
                        DebuffData[hero.CharName] = {}
                    end
                    table.insert(DebuffData[hero.CharName], { Name = sumName, Type = BuffType.Damage, Slot = -1 })
                end
            end
        end
    end
end

local IsValidTarget = function(target, range)
    return TS:IsValidTarget(target, range)
end

local GetDistanceSqr = function(p1, p2)
    local dx = p1.x - p2.x
    local dz = p1.z - p2.z
    return (dx * dx) + (dz * dz)
end

local UpdateProperty = function(handle, property, value)
    Heroes[handle][property].LastUpdate = value
end

local GetMenuValue = function(item)
    return Menu.Get(item, true)
end

local CalculateIncomingDamage = function(target, time)
    local target = target and target.AsAI
    if not target then return 0 end
    local _caster = nil
    local time = time or math.huge
    local damage = _G.Libs.HealthPred.GetDamagePrediction(target, time)

    local detectedSS = Evade.GetDetectedSkillshots()
    for k, spell in pairs(detectedSS) do
        if spell:IsAboutToHit(time, target) then
            local spellName = spell:GetName()
            local caster = spell:GetCaster()
            if caster ~= target then
                damage = damage + DamageLib.GetSpellDamage(caster, target, spellName)
                _caster = caster
            end
        end
    end

    for k, spell in pairs(DetectedTargetMissiles) do
        local missileName = spell.Name
        local caster = spell.Caster
        local mTarget = spell.Target
        if mTarget == target then
            if not spell.IsBasicAttack then
                damage = damage + DamageLib.GetSpellDamage(caster, target, missileName)
                _caster = caster
            end
        end
    end

    for k, spell in pairs(DetectedTargetSpells) do
        local name = spell.Name
        local caster = spell.Caster
        local mTarget = spell.Target
        if mTarget == target then
            damage = damage + DamageLib.GetSpellDamage(caster, target, name)
            _caster = caster
        end
    end

    if Buffs[target.Handle] then
        for k, buff in pairs(Buffs[target.Handle]) do
            local caster = buff.Caster
            if buff.Active and caster.IsValid and caster ~= target then
                damage = damage + DamageLib.GetBuffDamage(caster, target, buff)
                _caster = caster
            end
        end
    end

    for k, particle in pairs(DetectedParticles) do
        local name = particle.Name
        local caster = particle.Caster
        local position = particle.Position
        if not particle.FixedPosition then
            position = caster.Position
        end
        if particle.UpdatePosition == 1 then
            if particle.Object and particle.Object.Position then
                position = particle.Object.Position
            end
        end
        local range = particle.Range
        if caster ~= target and GetDistanceSqr(position, target.Position) < range * range then
            damage = damage + DamageLib.GetSpellDamage(caster, target, name)
            _caster = caster
        end
    end

    return damage, _caster
end

local AddAlliesToMenu = function(id)
    Menu.NewTree(
        id .. "_Whitelist",
        "Allies Whitelist",
        function()
            for handle, hero in pairs(Heroes) do
                if hero.IsAlly then
                    Menu.Checkbox(id .. "_Whitelist_" .. hero.CharName, "Use On: " .. hero.CharName, true)
                end
            end
        end
    )
end

local AddEnemiesToMenu = function(id)
    Menu.NewTree(
        id .. "_Whitelist",
        "Enemies Whitelist",
        function()
            for handle, hero in pairs(Heroes) do
                if hero.IsEnemy then
                    Menu.Checkbox(id .. "_Whitelist_" .. hero.CharName, "Use On: " .. hero.CharName, false)
                end
            end
        end
    )
end

local AddDebuffsToMenu = function(id)
    Menu.NewTree(
        id .. "_Debuffs",
        "Debuffs",
        function()
            for handle, hero in pairs(Heroes) do
                if hero.IsEnemy then
                    local charName = hero.CharName
                    if DebuffData[charName] then
                        for k, buffData in pairs(DebuffData[charName]) do
                            Menu.Checkbox(id .. "_Debuffs_" .. charName .. "_" .. buffData.Name, charName .. " | " .. SlotToString[buffData.Slot] .. " | " .. buffData.Name, true)
                        end
                    end
                end
            end
        end
    )
end

local AddAllyDebuffsToMenu = function(id)
    Menu.NewTree(
        id .. "_AllyDebuffs",
        "Ally Debuffs",
        function()
            for handle, hero in pairs(Heroes) do
                local charName = hero.CharName
                if hero.IsAlly then
                    local new_id = id .. "_AllyDebuffs_" .. charName
                    if GetMenuValue(id .. "_Whitelist_" .. hero.CharName) or MenuIsLoading then
                        Menu.NewTree(
                            id .. "_AllyDebuffs_" .. charName,
                            charName,
                            function()
                                for handle, hero in pairs(Heroes) do
                                    if hero.IsEnemy then
                                        local charName = hero.CharName
                                        if DebuffData[charName] then
                                            for k, buffData in pairs(DebuffData[charName]) do
                                                Menu.Checkbox(new_id .. "_" .. charName .. "_" .. buffData.Name, charName .. " | " .. SlotToString[buffData.Slot] .. " | " .. buffData.Name, true)
                                            end
                                        end
                                    end
                                end
                            end
                        )
                    end
                end
            end
        end
    )
end

local AddToMenu = function(itemType, summoners)
    local data = summoners and SummonerData or ItemData
    for dataID, item in pairs(data) do
        local config = item.Config
        if item.Type == itemType or summoners then
            Menu.NewTree(
                "S_Activator_" .. dataID,
                item.Name,
                function()
                    local id = "S_Activator_" .. dataID
                    Menu.Checkbox(id .. "_Enabled", "Use " .. item.Name, true)
                    if config.AddOnlyCombo then
                        if Menu.Checkbox(id .. "_Combo", "Use Only In Combo & Harass", false) or MenuIsLoading then
                            if config.AddIgnoreCombo then
                                Menu.Checkbox(id .. "_IgnoreCombo", "^ Ignore This Option If Next Spell Will Kill You", true)
                            end
                        end
                    end
                    if config.AddOwnMaxHealth then
                        local defaultValue = config.DefaultHealthValue or 10
                        Menu.Slider(id .. "OwnMaxHealth", "Max Own Health To Use [%]", defaultValue, 0, 100, 1)
                    end
                    if config.AddEnemyMaxHealth then
                        local defaultValue = config.DefaultHealthValue or 10
                        Menu.Slider(id .. "EnemyMaxHealth", "Max Enemy Health To Use [%]", defaultValue, 0, 100, 1)
                    end
                    if config.AddAllyCount then
                        Menu.Slider(id .. "AllyCount", "Ally Count To Cast", 2, 1, 5, 1)
                    end
                    if config.AddEnemyCount then
                        Menu.Slider(id .. "EnemyCount", "Enemy Count To Cast", 2, 1, 5, 1)
                    end
                    if config.AddAllies then
                        if Menu.Checkbox(id .. "_Ally", "Use On Allies", true) or MenuIsLoading then
                            if GetMenuValue(id .. "_Ally") then
                                AddAlliesToMenu(id)
                                if config.AddAllyDebuffs then
                                    AddAllyDebuffsToMenu(id)
                                end
                                if config.AddAllyMaxHealth then
                                    local defaultValue = config.DefaultHealthValue or 10
                                    Menu.Slider(id .. "AllyMaxHealth", "Max Ally Health To Use [%]", defaultValue, 0, 100, 1)
                                end
                            end
                        end
                    end
                    if config.AddEnemies then
                        if Menu.Checkbox(id .. "_Enemy", "Use On Enemy", true) or MenuIsLoading then
                            if GetMenuValue(id .. "_Enemy") then
                                AddEnemiesToMenu(id)
                            end
                        end
                    end
                    if config.AddDebuffs then
                        AddDebuffsToMenu(id)
                    end
                    if config.AddDelay then
                        Menu.Slider(id .. "Delay", "Cast Delay", 50, 0, 500, 1)
                    end
                end
            )
        end
    end
end

local GetConditionValue = function(id, itemData, itemId)
    local itemId = itemId or 0
    local condition = true
    local myPosition = Heroes[myHero.Handle]["Position"].Value
    if itemData.Config.AddOnlyCombo then
        if GetMenuValue(id .. "_Combo") then
            local mode = Orbwalker.GetMode()
            if (mode ~= "Combo" and mode ~= "Harass") or not CurrentTarget then
                condition = false
            end
            if GetMenuValue(id .. "_IgnoreCombo") then
                local damage = CalculateIncomingDamage(myHero)
                if (damage > myHero.Health + myHero.ShieldAll) then
                    condition = true
                end
            end
        end
    end
    if itemData.CastRange and itemData.CastRange > 0 then
        local target = CurrentTarget
        if target and Heroes[target.Handle] then
            local position = Heroes[target.Handle]["Position"].Value
            local dist = GetDistanceSqr(myPosition, position) > itemData.CastRange * itemData.CastRange
            if dist then
                condition = false
            end
        else
            condition = false
        end
    end
    if itemData.EffectRadius and itemData.EffectRadius > 0 and itemData.CastRange == 0 then
        local target = CurrentTarget
        if target and Heroes[target.Handle] then
            local position = Heroes[target.Handle]["Position"].Value
            local dist = GetDistanceSqr(myPosition, position) > itemData.EffectRadius * itemData.EffectRadius
            if dist then
                condition = false
            end
        else
            condition = false
        end
        if itemData.Config.AddAllyCount then
            local allyCountValue = GetMenuValue(id .. "AllyCount")
            if AllyCount and (AllyCount[itemId] and AllyCount[itemId] < allyCountValue) or not EnemyIsNear then
                condition = false
            end
        end
    end
    if itemData.Config.AddEnemyCount then
        local EnemyCountValue = GetMenuValue(id .. "EnemyCount")
        if EnemyCount < EnemyCountValue then
            condition = false
        end
    end
    return condition
end

local GetHealthConditionValue = function(hero, id, itemData)
    local condition = true
    local ownMaxHealth = 0
    local allyMaxHealth = 0
    local myPosition = Heroes[myHero.Handle]["Position"].Value
    if hero.IsEnemy and itemData.Config.AddEnemyMaxHealth and CurrentTarget then
        local menuValue = GetMenuValue(id .. "EnemyMaxHealth") * 0.01
        local health = CurrentTarget.HealthPercent
        if menuValue < health then
            condition = false
        end
    end
    if hero.IsAlly and itemData.Config.AddAllyMaxHealth and GetMenuValue(id .. "_Ally") then
        local menuValue = GetMenuValue(id .. "AllyMaxHealth") * 0.01
        allyMaxHealth = menuValue
    end
    if hero.IsMe and itemData.Config.AddOwnMaxHealth then
        local menuValue = GetMenuValue(id .. "OwnMaxHealth") * 0.01
        local health = myHero.HealthPercent
        ownMaxHealth = menuValue
        if menuValue < health then
            condition = false
        end
    end
    return condition, ownMaxHealth, allyMaxHealth
end

local RecacheSmiteDamage = function()
    for k, v in pairs(myHero.Buffs) do
        if v.Name:find("SmiteDamageTracker") then
            CachedSmiteDamage = v.Count
        end
    end
end

----------------------------------------------------------------------------------------------

local OnUpdate = function()
    local tick = Game.GetTime()
    for handle, hero in pairs(ObjectManager.Get("all", "heroes")) do
        if Heroes[handle] then
            local data = Heroes[handle]
            for k, property in pairs({ "Position", "IsDead", "IsVisible", "IsOnScreen", "HealthPercent", "IsTargetable" }) do
                --// Update //--
                local lastUpdate = data[property].LastUpdate
                local updateInterval = data[property].UpdateInterval
                if lastUpdate + updateInterval < tick then
                    local value = hero[property]
                    data[property].Value = value
                    data[property].LastUpdate = tick
                end
                
                --// OnScreen Callback //--
                local isOnScreen = data["IsOnScreen"].Value
                if not VisionTable[handle] then
                    VisionTable[handle] = {
                        isOnScreen = isOnScreen
                    }
                end
                if OnScreenCallback ~= {} then
                    if isOnScreen and VisionTable[handle] and not VisionTable[handle].isOnScreen then
                        VisionTable[handle] = {
                            isOnScreen = isOnScreen
                        }
                        for _, f in pairs(OnScreenCallback) do
                            f(data, true)
                        end
                    elseif not isOnScreen and VisionTable[handle] and VisionTable[handle].isOnScreen then
                        VisionTable[handle] = {
                            isOnScreen = isOnScreen
                        }
                        for _, f in pairs(OnScreenCallback) do
                            f(data, false)
                        end
                    end
                end
            end

            local isDead = data["IsDead"].Value
            if not isDead then
                local isVisible = data["IsVisible"].Value
                local isOnScreen = data["IsOnScreen"].Value
                if isVisible and isOnScreen then
                    UpdateProperty(data.Handle, "Position", 0)
                end
            end
        end
    end
end

local OnTick = function()
    local myPosition = Heroes[myHero.Handle]["Position"].Value
    local enemies = {}
    local tick = Game.GetTime()
    if ItemLastUpdate + ItemUpdateInterval < tick then
        for slot, item in pairs(myHero.Items) do
            Items[slot + 6] = item
            ItemLastUpdate = tick
        end
    end
    if Heroes[myHero.Handle] then
        local position = Heroes[myHero.Handle]["Position"].Value
        if GetDistanceSqr(BasePosition, position) < 1000000 then
            ItemLastUpdate = 0.5
        end
    end
    if TargetLastUpdate + TargetUpdateInterval < tick then
        CurrentTarget = TS:GetTarget(1000)
        TargetLastUpdate = tick
    end

    EnemyCount = 0
    EnemyIsNear = false
    EnemyIsNearAroundAlly = {}
    AllyCount = {
        [ItemID.ShurelyasBattlesong] = 0,
        [ItemID.LocketOftheIronSolari] = 0,
    }
    for handle, hero in pairs(Heroes) do
        if not hero.IsDead.Value then
            if hero.IsAlly then
                local dist = GetDistanceSqr(myPosition, hero["Position"].Value)
                if dist < 1000 * 1000 then
                    AllyCount[ItemID.ShurelyasBattlesong] = AllyCount[ItemID.ShurelyasBattlesong] + 1
                end
                if dist < 800 * 800 then
                    AllyCount[ItemID.LocketOftheIronSolari] = AllyCount[ItemID.LocketOftheIronSolari] + 1
                end
            end
            if hero.IsEnemy then
                enemies[handle] = hero
                local dist = GetDistanceSqr(myPosition, hero["Position"].Value)
                if dist < 400 * 400 then
                    EnemyCount = EnemyCount + 1
                end
                if dist < 1300 * 1300 then
                    EnemyIsNear = true
                end
            else
                for k, v in pairs(enemies) do
                    local dist = GetDistanceSqr(hero["Position"].Value, v["Position"].Value)
                    if dist < 1000 * 1000 then
                        EnemyIsNearAroundAlly[handle] = true
                    end
                end
            end
        end
    end
end

local SmiteIsEnabled = function()
    return GetMenuValue("S_Activator_Summoners_Smite_Enabled") and 
        (GetMenuValue("S_Activator_Summoners_Smite_Toggle") or 
        GetMenuValue("S_Activator_Summoners_Smite_HotKey"))
end

local OnDraw = function()
    if SmiteSpell then
        if GetMenuValue("S_Activator_Summoners_Smite_DrawStatus") then
            if SmiteIsEnabled() then
                Renderer.DrawTextOnPlayer("AutoSmite: Enabled", 0x00FF00FF)
            else
                Renderer.DrawTextOnPlayer("AutoSmite: Disabled", 0xFF0000FF)
            end
        end
        if GetMenuValue("S_Activator_Summoners_Smite_DrawRange") and SmiteSpell:IsReady() then 
            Renderer.DrawCircle3D(Player.Position, 575, 30, 2, 0xFFFF00FF)
        end
    end
end

local SummonerActivatorLogic = function()
    local myPosition = Heroes[myHero.Handle]["Position"].Value
    for slot, item in pairs(Summoners) do
        local name = item.Name
        local itemData = SummonerData[name]
        local id = "S_Activator_" .. name 
        local itemEnabled = id .. "_Enabled"
        if GetMenuValue(itemEnabled) then
            local condition = GetConditionValue(id, itemData)
            if condition then
                local spell = myHero:GetSpell(slot)
                local spellIsReady = myHero:GetSpellState(slot) == 0
                if spell and spellIsReady then
                    if name == "SummonerBoost" then
                        local castDelay = GetMenuValue(id .. "Delay")
                        local id = id .. "_Debuffs_"
                        for k, buff in pairs(Buffs[myHero.Handle]) do
                            if buff.Active and buff.Caster then
                                local source = Heroes[buff.Caster.Handle]
                                if source then
                                    local sourceCharName = Heroes[buff.Caster.Handle].CharName
                                    if GetMenuValue(id .. sourceCharName .. "_" .. buff.Name) then
                                        delay(castDelay, function()
                                            return Input.Cast(slot)
                                        end)
                                    end
                                end
                            end
                        end
                    elseif name == "SummonerHeal" or name == "SummonerBarrier" then
                        for handle, hero in pairs(Heroes) do
                            local position = hero["Position"].Value
                            if hero.IsAlly and not hero.IsDead.Value then
                                local checkDist = itemData.CastRange > 0
                                local whiteList = GetMenuValue(id .. "_Whitelist_" .. hero.CharName) or hero.IsMe
                                if whiteList then
                                    if checkDist and GetDistanceSqr(myPosition, position) < (itemData.CastRange * itemData.CastRange) or not checkDist then
                                        local damage = CalculateIncomingDamage(hero.Object)
                                        local realHP = hero.Object.Health + hero.Object.ShieldAll - 50
                                        local healthCondition, ownMaxHealth, allyMaxHealth = GetHealthConditionValue(hero, id, itemData)
                                        if damage > realHP or healthCondition then
                                            local maxHealth = hero.IsMe and ownMaxHealth or allyMaxHealth
                                            if damage > realHP or hero.Object.HealthPercent < maxHealth and EnemyIsNearAroundAlly[handle] then
                                                if itemData.CastType == CastType.Active then
                                                    return Input.Cast(slot)
                                                elseif itemData.CastType == CastType.Targeted then
                                                    return Input.Cast(slot, hero.AsAttackableUnit)
                                                end
                                            end
                                        end
                                    end
                                end
                            end
                        end
                    elseif name == "SummonerDot" then
                        for handle, hero in pairs(Heroes) do
                            local position = hero["Position"].Value
                            local dist = GetDistanceSqr(myPosition, position) < (itemData.CastRange * itemData.CastRange)
                            if hero.IsEnemy and not hero.IsDead.Value and hero.IsTargetable.Value and dist then
                                local incDamage = CalculateIncomingDamage(hero.Object)
                                local damage = DamageLib.GetSpellDamage(myHero, hero.Object, name, "TotalDamage")
                                local realHP = (hero.Object.Health + hero.Object.ShieldAll) - incDamage
                                if damage > realHP then
                                    return Input.Cast(slot, hero.Object.AsAttackableUnit)
                                end
                            end
                        end
                    elseif name == "SummonerExhaust" then
                        --[[
                        for handle, hero in pairs(Heroes) do
                            local position = hero["Position"].Value
                            --local dist = GetDistanceSqr(myPosition, position) < (itemData.CastRange * itemData.CastRange)
                            if hero.IsAlly and not hero.IsDead.Value and hero.IsTargetable.Value then
                                local hp = hero.Object.Health
                                local maxHp = hero.Object.MaxHealth
                                local incDamage, caster = CalculateIncomingDamage(hero.Object)
                                local realHP = (hero.Object.Health + hero.Object.ShieldAll) - incDamage
                                if caster and incDamage > 0 and (incDamage / hp) > 01 then
                                    return Input.Cast(slot, hero.Object.AsAttackableUnit)
                                end
                            end
                        end]]
                    end
                end
            end
        end
    end
end

local ShieldActivatorLogic = function()
    local charName = Heroes[myHero.Handle]["CharName"]
    local myPosition = Heroes[myHero.Handle]["Position"].Value
    local ownMaxHealth = 0
    local allyMaxHealth = 0
    if ShieldData[charName] and ShieldSpell then
        local itemData = ShieldData[charName]
        local name = itemData.Name
        local slot = itemData.Slot
        local id = "S_Activator_AutoShield_" .. charName 
        local itemEnabled = id .. "_Enabled"
        if GetMenuValue(itemEnabled) and ShieldSpell:IsReady() then
            local condition = GetConditionValue(id, itemData)
            if condition then
                for handle, hero in pairs(Heroes) do
                    local position = hero["Position"].Value
                    if hero.IsAlly and not hero.IsDead.Value then
                        local whiteList = GetMenuValue(id .. "_Whitelist_" .. hero.CharName) or hero.IsMe
                        if whiteList then
                            if GetDistanceSqr(myPosition, position) < (itemData.Range * itemData.Range) then
                                local damage = CalculateIncomingDamage(hero.Object)
                                local realHP = hero.Object.Health + hero.Object.ShieldAll - 50
                                local healthCondition, ownMaxHealth, allyMaxHealth = GetHealthConditionValue(hero, id, itemData)
                                if damage > realHP or healthCondition then
                                    local maxHealth = hero.IsMe and ownMaxHealth or allyMaxHealth
                                    if damage > 0 or maxHealth < 0.05 then
                                        if (damage > hero.Object.Health + hero.Object.ShieldAll) or
                                        (hero.Object.HealthPercent < maxHealth and EnemyIsNearAroundAlly[hero.Handle]) then
                                            if itemData.CastType == CastType.Active then
                                                return Input.Cast(slot)
                                            elseif itemData.CastType == CastType.Targeted then
                                                return Input.Cast(slot, hero.Object.AsAttackableUnit)
                                            elseif itemData.CastType == CastType.Skillshot then
                                                if hero.IsMe then
                                                    return ShieldSpell:Cast(hero.Object.Position)
                                                else
                                                    return ShieldSpell:CastOnHitChance(hero.Object, HitChance.Low)
                                                end
                                            end
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end

local ItemActivatorLogic = function()
    local myPosition = Heroes[myHero.Handle]["Position"].Value
    for slot, item in pairs(Items) do
        local itemID = item.ItemId
        local itemData = ItemData[itemID]
        local id = "S_Activator_" .. itemID 
        local itemEnabled = id .. "_Enabled"
        if GetMenuValue(itemEnabled) then
            local condition = GetConditionValue(id, itemData, itemID)
            if condition then
                local spell = myHero:GetSpell(slot)
                local spellIsReady = myHero:GetSpellState(slot) == 0
                if spell and spellIsReady then
                    if itemData.Type == ItemType.Defensive then
                        if itemID == ItemID.RanduinsOmen then
                            return Input.Cast(slot)
                        else
                            for handle, hero in pairs(Heroes) do
                                local position = hero["Position"].Value
                                if hero.IsAlly and not hero.IsDead.Value then
                                    local checkDist = itemData.EffectRadius > 0
                                    local whiteList = GetMenuValue(id .. "_Whitelist_" .. hero.CharName) or hero.IsMe
                                    if whiteList then
                                        local damage = CalculateIncomingDamage(hero.Object)
                                        local realHP = hero.Object.Health + hero.Object.ShieldAll - 50
                                        local healthCondition, ownMaxHealth, allyMaxHealth = GetHealthConditionValue(hero, id, itemData)
                                        if damage > realHP or healthCondition then
                                            if checkDist and GetDistanceSqr(myPosition, position) < (itemData.EffectRadius * itemData.EffectRadius) or not checkDist then
                                                if itemID == ItemID.ZhonyasHourglass or itemID == ItemID.Stopwatch then
                                                    if damage > realHP then
                                                        return Input.Cast(slot)
                                                    end
                                                else
                                                    if damage > 0 then
                                                        local maxHealth = hero.IsMe and ownMaxHealth or allyMaxHealth
                                                        if damage > realHP or hero.Object.HealthPercent < maxHealth and EnemyIsNearAroundAlly[handle] then
                                                            if itemData.CastType == CastType.Active then
                                                                return Input.Cast(slot)
                                                            elseif itemData.CastType == CastType.Skillshot then
                                                                local position = Heroes[myHero.Handle]["Position"].Value
                                                                local pred = Prediction.GetPredictedPosition(hero.Object, itemData.PredictionInput, position)
                                                                if pred and pred.HitChanceEnum >= Enums.HitChance.Medium then
                                                                    return Input.Cast(slot, pred.CastPosition)
                                                                end
                                                            end
                                                        end
                                                    end
                                                end
                                            end
                                        end
                                    end
                                end
                            end
                        end
                    end
                    local enemyHealthCondition = nil
                    local healthCondition = GetHealthConditionValue(myHero, id, itemData)
                    if CurrentTarget then
                        enemyHealthCondition = GetHealthConditionValue(CurrentTarget, id, itemData)
                    end
                    if itemData.Type == ItemType.Offensive then
                        if healthCondition then
                            if itemData.CastType == CastType.Active then
                                return Input.Cast(slot)
                            end
                        end
                        if itemData.CastType == CastType.Targeted then
                            if enemyHealthCondition and CurrentTarget then
                                return Input.Cast(slot, CurrentTarget.AsAttackableUnit)
                            end
                        end
                        if itemData.CastType == CastType.Skillshot then
                            if enemyHealthCondition and CurrentTarget then
                                local position = Heroes[myHero.Handle]["Position"].Value
                                local pred = Prediction.GetPredictedPosition(CurrentTarget, itemData.PredictionInput, position)
                                if pred and pred.HitChanceEnum >= Enums.HitChance.Medium then
                                    return Input.Cast(slot, pred.CastPosition)
                                end
                            end
                        end
                    end
                    if healthCondition then
                        if itemData.Type == ItemType.Consumable then
                            if not PotionBuff 
                            and not Player.IsRecalling 
                            and not Player.IsInFountain then
                                return Input.Cast(slot)
                            end
                        end
                    end
                    if itemData.Type == ItemType.Instant then
                        return Input.Cast(slot)
                    end
                    if itemData.Type == ItemType.Cleanse then
                        local castDelay = GetMenuValue(id .. "Delay")
                        if itemData.CastType == CastType.Active then
                            local id = id .. "_Debuffs_"
                            for k, buff in pairs(Buffs[myHero.Handle]) do
                                if buff.Active and buff.Caster then
                                    local source = Heroes[buff.Caster.Handle]
                                    if source then
                                        local sourceCharName = Heroes[buff.Caster.Handle].CharName
                                        if GetMenuValue(id .. sourceCharName .. "_" .. buff.Name) then
                                            delay(castDelay, function()
                                                return Input.Cast(slot)
                                            end)
                                        end
                                    end
                                end
                            end
                        elseif itemData.CastType == CastType.Targeted then
                            local id = id .. "_AllyDebuffs_"
                            for k, hero in pairs(Heroes) do
                                local position = Heroes[hero.Handle]["Position"].Value
                                if hero.IsAlly and GetDistanceSqr(myPosition, position) < itemData.CastRange * itemData.CastRange then
                                    local id = id .. hero.CharName .. "_"
                                    for k, buff in pairs(Buffs[hero.Handle]) do
                                        if buff.Active and buff.Caster then
                                            local source = Heroes[buff.Caster.Handle]
                                            if source then
                                                local sourceCharName = Heroes[buff.Caster.Handle].CharName
                                                if GetMenuValue(id .. sourceCharName .. "_" .. buff.Name) then
                                                    return Input.Cast(slot, hero.Object.AsAttackableUnit)
                                                end
                                            end
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end

local SmiteActivatorLogic = function()
    if not SmiteSpell then return end
    local nearbyMonsters = ObjectManager.GetNearby("neutral", "minions")
    if #nearbyMonsters == 0 then return end

    local ignoreWhitelist = false
    if GetMenuValue("S_Activator_Summoners_Smite_EnemyNear") then
        for k, hero in ipairs(EnemyJunglers) do  
            if hero.IsValid and hero.IsTargetable then
                ignoreWhitelist = true
                break
            end
        end
    end

    if not ignoreWhitelist and GetMenuValue("S_Activator_Summoners_Smite_EnemyTerritory") then
        ignoreWhitelist = myHero.IsInEnemyJungle or myHero.IsInDragonPit or myHero.IsInBaronPit
    end
    if SmiteIsEnabled() then
        local myPosition = Heroes[myHero.Handle]["Position"].Value
        for k, obj in ipairs(nearbyMonsters) do       
            local mob = obj.AsMinion
            if BigJungleMonsters[mob.CharName] then
                local canSmite = ignoreWhitelist or GetMenuValue("S_Activator_Summoners_Smite_WhiteList_" .. mob.CharName)
                if canSmite and mob:EdgeDistance(myPosition) <= 500 and mob.IsTargetable then
                    if mob.Health <= CachedSmiteDamage then
                        return SmiteSpell:Cast(mob)
                    end
                end 
            end       
        end
    end
end

local HasItem = function(itemId)
    for itemSlot, item in pairs(myHero.Items) do
        if item and item.ItemId == itemId then
            return itemSlot, item
        end
    end
    return nil, nil
end

local GetWardSlot = function()
    for k, v in pairs(WardData) do
        if GetMenuValue("S_Activator_AutoJump_WardList_" .. k) then
            local slot, item = HasItem(k)
            if slot then
                slot = slot + 6
                if myHero:GetSpellState(slot) == SpellStates.Ready then
                    return slot
                end
            end
        end
    end
    return nil
end

local AutoJumpLogic = function(i)
    if not AutoJumpData[myCharName] then
        return
    end

    if not GetMenuValue("S_Activator_AutoJump_Enabled") then
        return
    end

    if not GetMenuValue("S_Activator_AutoJump_HotKey") then
        return
    end

    if not AutoJumpSpell then
        return
    end

    if not AutoJumpSpell:IsReady() then
        return
    end 

    local time = Game.GetTime()
    local bestTarget = nil
    local bestDist = 0
    local data = AutoJumpData[myCharName]
    local config = data.Config
    local myPosition = Heroes[myHero.Handle]["Position"].Value
    local mousePosition = Renderer.GetMousePos()

    if data.SpellName then
        local spellName = AutoJumpSpell:GetName()
        if spellName ~= data.SpellName then
            return
        end
    end

    if config.Ward then
        local allyWards = ObjectManager.GetNearby("ally", "wards")
        for k, ward in pairs(allyWards) do
            if ward and ward.IsTargetable then
                local minionPosition = ward.Position
                if GetDistanceSqr(myPosition, minionPosition) < data.CastRange * data.CastRange then
                    local extPosition = myPosition:Extended(minionPosition, data.CastRange)
                    local dist1 = GetDistanceSqr(myPosition, minionPosition)
                    local dist2 = GetDistanceSqr(mousePosition, minionPosition)
                    local dist3 = GetDistanceSqr(mousePosition, myPosition)
                    if dist2 < dist1 and dist3 > bestDist then
                        bestTarget = ward
                        bestDist = dist3
                    end
                end
            end
        end
    end

    if config.EnemyMinion then
        local enemyMinions = ObjectManager.GetNearby("enemy", "minions")
        for k, minion in pairs(enemyMinions) do
            if minion and minion.IsTargetable then
                local minionPosition = minion.Position
                if GetDistanceSqr(myPosition, minionPosition) < data.CastRange * data.CastRange then
                    local extPosition = myPosition:Extended(minionPosition, data.CastRange)
                    local dist1 = GetDistanceSqr(myPosition, minionPosition)
                    local dist2 = GetDistanceSqr(mousePosition, minionPosition)
                    local dist3 = GetDistanceSqr(mousePosition, myPosition)
                    if dist2 < dist1 and dist3 > bestDist then
                        bestTarget = minion
                        bestDist = dist3
                    end
                end
            end
        end
    end

    if config.AllyMinion then
        local allyMinions = ObjectManager.GetNearby("ally", "minions")
        for k, minion in pairs(allyMinions) do
            if minion and minion.IsTargetable then
                local minionPosition = minion.Position
                if GetDistanceSqr(myPosition, minionPosition) < data.CastRange * data.CastRange then
                    local extPosition = myPosition:Extended(minionPosition, data.CastRange)
                    local dist1 = GetDistanceSqr(myPosition, minionPosition)
                    local dist2 = GetDistanceSqr(mousePosition, minionPosition)
                    local dist3 = GetDistanceSqr(mousePosition, myPosition)
                    if dist2 < dist1 and dist3 > bestDist then
                        bestTarget = minion
                        bestDist = dist3
                    end
                end
            end
        end
    end

    if config.Ally then
        local allies = ObjectManager.GetNearby("ally", "heroes")
        for k, hero in pairs(allies) do
            if hero and hero.IsTargetable then
                local heroPosition = hero.Position
                if GetDistanceSqr(myPosition, heroPosition) < data.CastRange * data.CastRange then
                    local extPosition = myPosition:Extended(heroPosition, data.CastRange)
                    local dist1 = GetDistanceSqr(myPosition, heroPosition)
                    local dist2 = GetDistanceSqr(mousePosition, heroPosition)
                    local dist3 = GetDistanceSqr(mousePosition, myPosition)
                    if dist2 < dist1 and dist3 > bestDist then
                        bestTarget = hero
                        bestDist = dist3
                    end
                end
            end
        end
    end

    if config.Enemy then
        local enemies = ObjectManager.GetNearby("enemy", "heroes")
        for k, hero in pairs(enemies) do
            if hero and hero.IsTargetable then
                local heroPosition = hero.Position
                if GetDistanceSqr(myPosition, heroPosition) < data.CastRange * data.CastRange then
                    local extPosition = myPosition:Extended(heroPosition, data.CastRange)
                    local dist1 = GetDistanceSqr(myPosition, heroPosition)
                    local dist2 = GetDistanceSqr(mousePosition, heroPosition)
                    local dist3 = GetDistanceSqr(mousePosition, heroPosition)
                    if dist2 < dist1 and dist3 > bestDist then
                        bestTarget = hero
                        bestDist = dist3
                    end
                end
            end
        end
    end

    if config.Jungle then
        local minions = ObjectManager.GetNearby("neutral", "minions")
        for k, minion in pairs(minions) do
            if minion and minion.IsTargetable then
                local minionPosition = minion.Position
                if GetDistanceSqr(myPosition, minionPosition) < data.CastRange * data.CastRange then
                    local extPosition = myPosition:Extended(minionPosition, data.CastRange)
                    local dist1 = GetDistanceSqr(myPosition, minionPosition)
                    local dist2 = GetDistanceSqr(mousePosition, minionPosition)
                    local dist3 = GetDistanceSqr(mousePosition, myPosition)
                    if dist2 < dist1 and dist3 > bestDist then
                        bestTarget = minion
                        bestDist = dist3
                    end
                end
            end
        end
    end

    if bestTarget and i == 1 then
        AutoJumpSpell:Cast(data.CastType == CastType.Targeted and bestTarget.AsAttackableUnit or bestTarget.Position)
    elseif i == 2 then
        if not GetMenuValue("S_Activator_AutoJump_PlaceWard") then
            return
        end

        local wardSlot = GetWardSlot()

        if not wardSlot then
            return
        end

        ShouldWardJump = true

        if time < WardJumpLastCastT + 0.5 then
            return
        end

        local castPos = myPosition:Extended(mousePosition, 600)

        Input.Cast(wardSlot, castPos)
        WardJumpLastCastT = time
    end
end

local AutoLevelLogic = function()
    if not GetMenuValue("S_Activator_AutoLevel_Enabled") then
        return
    end

    if not LevelPresets[myCharName] then
        return
    end

    if myHero.SpellPoints < 1 then
        return
    end

    local menuID = "S_Activator_AutoLevel_" .. myCharName
    if not GetMenuValue("S_Activator_AutoLevel_" .. myCharName .."_Enabled") then
        return
    end

    if myHero.Level < GetMenuValue("S_Activator_AutoLevel_" .. myCharName .."_MinLevel") then
        return
    end

    local delayValue = GetMenuValue("S_Activator_AutoLevel_Delay")
    local mode = GetMenuValue(menuID .."_Mode")
    if mode < 2 then
        local modeS = mode == 0 and "highestRate" or "mostUsed"
        local QL, WL, EL, RL = 0, 0, 0, myCharName == "Karma" and 1 or 0
        local preset = LevelPresets[myCharName][modeS]
        if preset then
            for i = 1, myHero.Level do
                if preset[i] == "Q" then
                    QL = QL + 1
                elseif preset[i] == "W" then
                    WL = WL + 1
                elseif preset[i] == "E" then
                    EL = EL + 1
                elseif preset[i] == "R" then
                    RL = RL + 1
                end
            end
            local diffR = myHero:GetSpell(SpellSlots.R).Level - RL < 0
            local diffQ = myHero:GetSpell(SpellSlots.Q).Level - QL
            local diffW = myHero:GetSpell(SpellSlots.W).Level - WL
            local diffE = myHero:GetSpell(SpellSlots.E).Level - EL
            local lowest = 99
            local spell = nil

            if diffQ < lowest then
                lowest = diffQ
                spell = SpellSlots.Q
            end

            if diffW < lowest then
                lowest = diffW
                spell = SpellSlots.W
            end

            if diffE < lowest then
                lowest = diffE
                spell = SpellSlots.E
            end

            if diffR then
                spell = SpellSlots.R
            end

            if spell then
                return delay(delayValue, function()
                    return Input.LevelSpell(spell)
                end)
            end
        end
    else
        local order = { 
            { GetMenuValue(menuID .. "_CustomR"), SpellSlots.R,  myHero:CanLevelSpell(SpellSlots.R), myHero:GetSpell(SpellSlots.R).Level },
            { GetMenuValue(menuID .. "_CustomQ"), SpellSlots.Q,  myHero:CanLevelSpell(SpellSlots.Q), myHero:GetSpell(SpellSlots.Q).Level },
            { GetMenuValue(menuID .. "_CustomW"), SpellSlots.W,  myHero:CanLevelSpell(SpellSlots.W), myHero:GetSpell(SpellSlots.W).Level },
            { GetMenuValue(menuID .. "_CustomE"), SpellSlots.E,  myHero:CanLevelSpell(SpellSlots.E), myHero:GetSpell(SpellSlots.E).Level }
        }
        table.sort(order, function(a, b)
            return a[1] < b[1]
        end)
        for _, entry in pairs(order) do
            if entry[3] and entry[4] == 0 then
                return delay(delayValue, function()
                    return Input.LevelSpell(entry[2])
                end)
            end
        end
        for _, entry in pairs(order) do
            if entry[3] then
                return delay(delayValue, function()
                    return Input.LevelSpell(entry[2])
                end)
            end
        end
    end
end

local OnBuffGain = function(obj, buff)
    if obj.IsHero then
        if Buffs[obj.Handle] then
            Buffs[obj.Handle][buff.Name] = { 
                Name = buff.Name,
                Type = buff.BuffType,
                Caster = buff.Source,
                Active = true,
                EndTime = buff.EndTime,
                Duration = buff.Duration,
                Count = buff.Count,
            }
        end
        if obj.IsMe then
            if buff.BuffType == 14 then
                PotionBuff = true
            end
            if buff.Name:find("SmiteDamageTracker") then
                delay(1000, RecacheSmiteDamage)
            end
        end
        --DEBUG("CharName: %s | Buff: %s | Duration: %s", obj.CharName, buff.Name, buff.Duration)
        for k, v in pairs(DetectedTargetSpells) do
            if v.Target == obj then
                if v.OnBuffGain and v.OnBuffGain == buff.Name then
                    DetectedTargetSpells[k] = nil
                end
            end
        end
    end
end

local OnBuffUpdate = function(obj, buff)
    if obj.IsHero then
        if Buffs[obj.Handle] then
            Buffs[obj.Handle][buff.Name] = { 
                Name = buff.Name,
                Type = buff.BuffType,
                Caster = buff.Source,
                Active = true,
                EndTime = buff.EndTime,
                Duration = buff.Duration,
                Count = buff.Count,
            }
        end
        if obj.IsMe then
            if buff.BuffType == 14 then
                PotionBuff = true
            end
        end
    end
end

local OnBuffLost = function(obj, buff)
    if obj.IsHero then
        if Buffs[obj.Handle] then
            if Buffs[obj.Handle][buff.Name] then
                Buffs[obj.Handle][buff.Name].Active = false
            end
        end
        if obj.IsMe then
            if buff.BuffType == 14 then
                PotionBuff = false
            end
        end
    end
end

local OnCreateObject = function(obj)
    local missile = obj.AsMissile
    if missile then
        local spell = missile.SpellCastInfo
        if spell and spell.MissileName and missile.Target and missile.Caster and missile.Target ~= missile.Caster then
            DetectedTargetMissiles[obj.Handle] = {
                Name = spell.MissileName,
                Caster = missile.Caster,
                Target = missile.Target,
                IsBasicAttack = missile.IsBasicAttack,
            }
        end
    end

    if SpellParticles[obj.Name] then
        local charName = SpellParticles[obj.Name].CharName
        local range = SpellParticles[obj.Name].Range
        local fixedPosition = SpellParticles[obj.Name].FixedPosition
        local updatePosition = SpellParticles[obj.Name].UpdatePosition
        local caster = nil
        for k, v in pairs(Heroes) do
            if v.CharName == charName then -- v.IsEnemy
                caster = v.Object
            end
        end
        if caster then
            DetectedParticles[obj.Handle] = {
                Object = obj,
                Name = obj.Name,
                Position = obj.Position,
                Range = range,
                Caster = caster,
                FixedPosition = fixedPosition,
                UpdatePosition = updatePosition,
            }
        end
    end

    if ShouldWardJump and AutoJumpSpell then
        if obj and obj.IsAlly and obj.IsWard then
            local ward = obj.AsMinion
            if ward.MaxHealth > 1 and ward:Distance(myHero.Position) <= 600 then
                AutoJumpSpell:Cast(ward)
                ShouldWardJump = false
            end
        end
    end
end

local OnDeleteObject = function(obj)
    DetectedTargetMissiles[obj.Handle] = nil
    DetectedParticles[obj.Handle] = nil
end

local OnProcessSpell = function(unit, spell)
    if TargetSpells[unit.CharName] then
        if TargetSpells[unit.CharName][spell.Name] then 
            local data = TargetSpells[unit.CharName][spell.Name]
            local target = spell.Target
            local sDelay = data.Delay ~= nil and data.Delay * 1000 or 1000
            DetectedTargetSpells[unit.Handle .. spell.Name] = {
                Name = spell.Name,
                Caster = unit,
                Target = target,
                OnBuffGain = data.OnBuffGain
            }
            delay(sDelay, function()
                DetectedTargetSpells[unit.Handle .. spell.Name] = nil
            end)
        end
    end
end

local OnAttackComplete = function(unit, spell)
    local menuID = "S_Activator_AutoShield_" .. myCharName
    if not GetMenuValue(menuID .."_AllyAttack") then
        return
    end

    if not ShieldData[myCharName] then
        return
    end

    if not ShieldSpell then
        return
    end

    if not ShieldSpell:IsReady() then
        return
    end

    if unit.IsEnemy then
        return
    end

    if not spell.Target then
        return 
    end

    local data = ShieldData[myCharName]
    local target = spell.Target

    if not target.IsHero then
        return
    end

    if not spell.IsBasicAttack or spell.IsSpecialAttack then
        return
    end

    if not GetMenuValue(menuID .. "_Whitelist_" .. unit.CharName) then
        return
    end

    if myHero:Distance(unit) > data.Range then 
        return
    end

    return ShieldSpell:Cast(unit.AsAttackableUnit)
end

local BlockMinion = {
    TargetMinion = nil,
	GetMinion = false,
	ToggleCondition = false,
	BlockOnMsg = "Blocking Minion",
	FindingMsg = "Finding a Minion..",
	TextClipper = Vector(150, 15, 0),
	LocalTick = 0,
}

function BlockMinion.TurnOffBlockMinion()
	BlockMinion.TargetMinion = nil
	BlockMinion.GetMinion = false
end

function BlockMinion.BlockCondition()
    local useBlock = GetMenuValue("S_Activator_BlockMinion_Enabled")
    local blockKey = GetMenuValue("S_Activator_BlockMinion_Key")
	if useBlock and not blockKey then
		BlockMinion.TurnOffBlockMinion()
		return false
	end
	return useBlock and blockKey
end

function BlockMinion.GetTheClosetMinion()
	local closetMinion = nil
	local minionList = ObjectManager.GetNearby("ally", "minions")
	local mindis = 500
	for handle, minion in pairs(minionList) do
		local distance = Player:Distance(minion)
		local minionAI = minion.AsAI
		local isFacing = minionAI:IsFacing(Player, 120)
		if minionAI and distance < mindis and isFacing and minionAI.MoveSpeed > 0 and minionAI.Pathing.IsMoving and minionAI.IsVisible then
			local direction = minionAI.Direction
			if direction then
				closetMinion = minion
				mindis = distance
			end
		end
	end
	return closetMinion
end

function BlockMinion.OnTick()
	local tick = clock()
	if BlockMinion.LocalTick < tick then
		BlockMinion.LocalTick = tick + 0.1
		local cond = BlockMinion.BlockCondition()
		if cond then
			local tgminion = BlockMinion.TargetMinion
			if not BlockMinion.GetMinion then
				tgminion = BlockMinion.GetTheClosetMinion()
				if not tgminion then
					BlockMinion.TargetMinion = nil
					return
				end
				BlockMinion.TargetMinion = tgminion
				BlockMinion.GetMinion = true
			end
			if tgminion and tgminion.IsValid then
				local minionAI = tgminion.AsAI
				if minionAI then
					local direction = minionAI.Direction
					local isFacing = minionAI:IsFacing(Player, 160)
					if not isFacing then
						BlockMinion.TurnOffBlockMinion()
					else
						if direction and minionAI.Pathing.IsMoving and minionAI.IsVisible then
							local extend = minionAI.Position:Extended(direction, -150)
							local mousepos = Renderer:GetMousePos()
							local newextend = extend:Extended(mousepos, 40)
							Input.MoveTo(newextend)
						end
					end
				end
			end
		end
	end
end

function BlockMinion.OnDraw()
    local blockKey = GetMenuValue("S_Activator_BlockMinion_Key")
	if blockKey then
		local cond = BlockMinion.BlockCondition()
		BlockMinion.ToggleCondition = cond
		if cond then
			local color = 0x00FF00FF
			local text = BlockMinion.FindingMsg
			local tg = BlockMinion.TargetMinion
			if tg and tg.IsValid then
				local tgMinion = tg.AsAI
				if tgMinion then
					Renderer.DrawCircle3D(tgMinion.Position, 75, 15, 1, color)
					text = BlockMinion.BlockOnMsg
				end
			end
			Renderer.DrawTextOnPlayer(text, color)
		end
	end
end

local OnLoad = function()
    local function IsSmite(spell)
        return spell and spell.Name:lower():find("smite")
    end
    for slot = 4, 5 do
        local spell = myHero:GetSpell(slot)
        Summoners[slot] = spell
        if IsSmite(spell) then
            SmiteSpell = Spell.Targeted({
                Slot = slot, 
                Range = 500
            })
            RecacheSmiteDamage()
        end
    end

    if SmiteSpell then
        for k, obj in pairs(ObjectManager.Get("enemy", "heroes")) do  
            local hero = obj.AsHero
            if hero and (IsSmite(hero:GetSpell(4)) or IsSmite(hero:GetSpell(5))) then
                EnemyJunglers[#EnemyJunglers+1] = hero
            end
        end
    end

    --// Auto Shield Init //--
    if ShieldData[myCharName] then
        local data = ShieldData[myHero.CharName]
        if data.CastType == CastType.Active then
            ShieldSpell = Spell.Active({
                Slot = data.Slot,
                Range = data.Range,
            })
        elseif data.CastType == CastType.Targeted then
            ShieldSpell = Spell.Targeted({
                Slot = data.Slot,
                Range = data.Range,
            })
        elseif data.CastType == CastType.Skillshot then
            ShieldSpell = Spell.Skillshot({
                Slot = data.Slot,
                Range = data.Range,
                Delay = data.Delay,
                Width = data.Width,
                Speed = data.Speed
            })
        end
    end

    --// Auto Jump //--
    if AutoJumpData[myCharName] then
        local data = AutoJumpData[myCharName]
        if data.CastType == CastType.Targeted then
            AutoJumpSpell = Spell.Targeted({
                Slot = data.Slot,
                Range = data.CastRange,
            })
        elseif data.CastType == CastType.Skillshot then
            AutoJumpSpell = Spell.Skillshot({
                Slot = data.Slot,
                Range = data.CastRange,
            })
        end
    end

    --// Menu //--
    Menu.RegisterMenu(
        "SActivator",
        "Activator Settings",
        function()
            Menu.Checkbox("S_Activator_Disable", "Disable Activator", false)
            if ActivatorDisabled and not GetMenuValue("S_Activator_Disable") then
                Menu.ColoredText("Now Press F5 To Load Activator!", 0xFF0000FF, true)
                return true
            end
            if ActivatorDisabled then
                Menu.ColoredText("Activator Disabled", 0xFF0000FF, true)
                return true
            end
            if not ActivatorDisabled and GetMenuValue("S_Activator_Disable") then
                Menu.ColoredText("Now Press F5 To Unload Activator!", 0xFF0000FF, true)
                return true
            end

            Menu.Separator("Item Activator", true)

            Menu.NewTree(
                "S_Activator_Cleanse",
                "Cleanse Items",
                function()
                    AddToMenu(ItemType.Cleanse)
                end
            )

            Menu.NewTree(
                "S_Activator_Defensive",
                "Defensive Items",
                function()
                    AddToMenu(ItemType.Defensive)
                end
            )

            Menu.NewTree(
                "S_Activator_Offensive",
                "Offensive Items",
                function()
                    AddToMenu(ItemType.Offensive)
                end
            )

            Menu.NewTree(
                "S_Activator_Consumable",
                "Consumable Items",
                function()
                    AddToMenu(ItemType.Consumable)
                end
            )

            Menu.NewTree(
                "S_Activator_Instant",
                "Instant Items",
                function()
                    AddToMenu(ItemType.Instant)
                end
            )

            Menu.Separator("Summoner Activator", true)
            AddToMenu(nil, true)
            Menu.NewTree("S_Activator_Summoners_Smite", "Smite", function()
                local id = "S_Activator_Summoners_Smite"
                Menu.Checkbox(id .. "_Enabled", "Use Smite", true)
                Menu.Keybind(id .. "_Toggle", "-> On/Off Toggle", string.byte('M'), true, true)
                Menu.Keybind(id .. "_HotKey", "-> On/Off Hotkey", string.byte('V'))
                Menu.Checkbox(id .. "_DrawStatus", "Draw Smite Status", true)
                Menu.Checkbox(id .. "_DrawRange", "Draw Smite Range", true) 
                Menu.Checkbox(id .. "_EnemyTerritory", "Ignore Whitelist In Enemy Jungle", true)    
                Menu.Checkbox(id .. "_EnemyNear", "Ignore Whitelist If Enemy Jungler Nearby", true)
                Menu.NewTree(id .. "_WhiteList", "Whitelist", function()
                    for k, v in pairs(JungleMonsters) do
                        Menu.Checkbox(id .. "_WhiteList_" .. v.Name, v.DisplayName, v.Enabled)
                    end
                end)
            end)

            Menu.Separator("Other Features", true)

            Menu.NewTree(
                "S_Activator_BlockMinion",
                "Block Minion",
                function()
                    Menu.Checkbox("S_Activator_BlockMinion_Enabled", "Enabled", true)
                    Menu.Keybind("S_Activator_BlockMinion_Key", "-> Key", string.byte('Z'))
                end
            )

            Menu.NewTree(
                "S_Activator_AutoShield",
                "Auto Shield",
                function()
                    if ShieldData[myHero.CharName] then
                        local data = ShieldData[myHero.CharName]
                        local name = data.Name
                        local slot = SlotToString[data.Slot]
                        local id = "S_Activator_AutoShield_" .. myHero.CharName
                        local config = data.Config
                        Menu.Checkbox(id .. "_Enabled", "Use " .. myHero.CharName .. " | " .. slot .. " | " .. name, true)
                        if config.AddOnlyCombo then
                            Menu.Checkbox(id .. "_Combo", "Use Only In Combo & Harass", true)
                            if config.AddIgnoreCombo then
                                if GetMenuValue(id .. "_Combo") then
                                    Menu.Checkbox(id .. "_IgnoreCombo", "^ Ignore This Option If Next Spell Will Kill You", true)
                                end
                            end
                        end
                        if config.AddOwnMaxHealth then
                            Menu.Slider(id .. "OwnMaxHealth", "Max Own Health To Use [%]", 50, 0, 100, 1)
                        end
                        if config.AddEnemyMaxHealth then
                            Menu.Slider(id .. "EnemyMaxHealth", "Max Enemy Health To Use [%]", 50, 0, 100, 1)
                        end
                        if config.AddAllyCount then
                            Menu.Slider(id .. "AllyCount", "Ally Count To Cast", 2, 1, 5, 1)
                        end
                        if config.AddEnemyCount then
                            Menu.Slider(id .. "EnemyCount", "Enemy Count To Cast", 2, 1, 5, 1)
                        end
                        if config.AddAllies then
                            Menu.Checkbox(id .. "_Ally", "Use On Allies", false)
                            if GetMenuValue(id .. "_Ally") then
                                if config.AddOnAttack then
                                    Menu.Checkbox(id .. "_AllyAttack", "Use On Ally Attack", false)
                                end
                                AddAlliesToMenu(id)
                                if config.AddAllyDebuffs then
                                    AddAllyDebuffsToMenu(id)
                                end
                                if config.AddAllyMaxHealth then
                                    Menu.Slider(id .. "AllyMaxHealth", "Max Ally Health To Use [%]", 50, 0, 100, 1)
                                end
                            end
                        end
                    else
                        Menu.Text("-> Supported Shields Not Found ")
                    end
                end
            )

            Menu.NewTree(
                "S_Activator_AutoJump",
                "Auto Jump",
                function()
                    if AutoJumpData[myHero.CharName] then
                        local data = AutoJumpData[myHero.CharName]
                        local name = data.DisplayName
                        local slot = SlotToString[data.Slot]
                        local id = "S_Activator_AutoJump_"
                        local config = data.Config
                        Menu.Checkbox(id .. "Enabled", "Use " .. myHero.CharName .. " | " .. slot .. " | " .. name, true)
                        Menu.Keybind(id .. "HotKey", "-> Auto Jump Key", string.byte('A'))
                        if config.Ward then
                            Menu.Checkbox(id .. "PlaceWard", "Place Wards", true)
                            Menu.NewTree(
                                id .. "WardList",
                                "Allowed Wards",
                                function()
                                    local id = id .. "WardList_"
                                    for itemID, value in pairs(WardData) do
                                        Menu.Checkbox(id .. itemID, value.DisplayName, true)
                                    end
                                end
                            )
                        end
                    else
                        Menu.Text("-> Supported Jumps Not Found ")
                    end
                end
            )

            Menu.NewTree(
                "S_Activator_AutoLevel",
                "Auto Level",
                function()
                    Menu.Checkbox("S_Activator_AutoLevel_Enabled", "Enabled", true)
                    local data = LevelPresets[myCharName]
                    if data then
                        local id = "S_Activator_AutoLevel_" .. myCharName
                        Menu.Checkbox(id .. "_Enabled", "Use For " .. myHero.CharName, true)
                        Menu.Dropdown(id .. "_Mode", "Level Mode", 0, { "Highest WinRate", "Most Popular", "Custom Order" })

                        local order = ""
                        local mode = GetMenuValue(id .. "_Mode")
                        if mode < 2 then
                            local key = mode == 0 and "highestRate" or mode == 1 and "mostUsed"
                            for k, v in pairs(data[key]) do
                                local endS = k == 18 and "" or ", "
                                order = order .. v .. endS
                            end
                            Menu.Text("Order: " .. order)
                        else
                            Menu.Text("Custom Spell Order")
                            Menu.Slider(id .. "_CustomR", "R", 1, 1, 4)
                            Menu.Slider(id .. "_CustomQ", "Q", 2, 1, 4)
                            Menu.Slider(id .. "_CustomW", "W", 3, 1, 4)
                            Menu.Slider(id .. "_CustomE", "E", 4, 1, 4)
                        end
                        Menu.Slider(id .. "_MinLevel", "Start At Level", 2, 1, 18)
                        Menu.Slider("S_Activator_AutoLevel_Delay", "Delay (ms)", 100, 0, 5000)
                    end
                end
            )

            Menu.Separator("Version: " .. VERSION)
            Menu.Text("Last Update: " .. LAST_UPDATE)
            Menu.Text("Author: Shulepin")

            MenuIsLoading = false
        end
    )

    if GetMenuValue("S_Activator_Disable") then
        ActivatorDisabled = true
        return true
    end

    EventManager.RegisterCallback(Events.OnUpdate, OnUpdate)
    EventManager.RegisterCallback(Events.OnTick, OnTick)
    EventManager.RegisterCallback(Events.OnDraw, OnDraw)
    EventManager.RegisterCallback(Events.OnHighPriority, ItemActivatorLogic)
    EventManager.RegisterCallback(Events.OnHighPriority, SummonerActivatorLogic)
    EventManager.RegisterCallback(Events.OnHighPriority, ShieldActivatorLogic)
    EventManager.RegisterCallback(Events.OnHighPriority, AutoJumpLogic)
    EventManager.RegisterCallback(Events.OnExtremePriority, SmiteActivatorLogic)
    EventManager.RegisterCallback(Events.OnTick, AutoLevelLogic)
    EventManager.RegisterCallback(Events.OnBuffGain, OnBuffGain)
    EventManager.RegisterCallback(Events.OnBuffUpdate, OnBuffUpdate)
    EventManager.RegisterCallback(Events.OnBuffLost, OnBuffLost)
    EventManager.RegisterCallback(Events.OnCreateObject, OnCreateObject)
    EventManager.RegisterCallback(Events.OnDeleteObject, OnDeleteObject)
    EventManager.RegisterCallback(Events.OnProcessSpell, OnProcessSpell)
    EventManager.RegisterCallback(Events.OnSpellCast, OnAttackComplete)
    EventManager.RegisterCallback(Events.OnTick, BlockMinion.OnTick)
    EventManager.RegisterCallback(Events.OnDraw, BlockMinion.OnDraw)

    --[[
    EventManager.RegisterCallback(Events.OnDraw, function()
        local heroes = ObjectManager.Get("all", "heroes")
        for k, hero in pairs(heroes) do
            local heroAI = hero.AsAI
            if hero.IsVisible and hero.IsOnScreen and not hero.IsDead then
                local damage = CalculateIncomingDamage(hero)
                local hpBarPos = heroAI.HealthBarScreenPos
                local x = 106 / (heroAI.MaxHealth + heroAI.ShieldAll)
                local position = (heroAI.Health + heroAI.ShieldAll) * x
                local value = math.min(position, damage * x)
                position = position - value
                Renderer.DrawFilledRect(Vector(hpBarPos.x + position - 45, hpBarPos.y - 23), Vector(value, 11), 1, 0xFFFFFFFF)
            end
        end
    end)

    EventManager.RegisterCallback(Events.OnCreateObject, function(obj)
        --if obj.IsParticle then
            --DEBUG("[OnCreateObject] Name: %s", obj.Name)
        --end
    end)

    EventManager.RegisterCallback(Events.OnDeleteObject, function(obj)
        --if obj.IsParticle then
            --DEBUG("[OnDeleteObject] Name: %s", obj.Name)
        --end
    end)]]

    return true
end

OnLoad()

----------------------------------------------------------------------------------------------