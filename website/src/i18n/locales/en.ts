import type { Translations } from "..";

const en: Translations = {
  meta: {
    description:
      "The galaxy obeys no one. Open-world space MMORPG — explore, fight, conquer.",
  },
  nav: {
    home: "Home",
    features: "Features",
    ships: "Ships",
    universe: "Universe",
    roadmap: "Roadmap",
    download: "Download",
    login: "Login",
    logout: "Logout",
    changeFaction: "Change faction",
    resetFaction: "Re-choose (show selector)",
  },
  hero: {
    badge: "Alpha 0.1 — Early Access",
    taglineDefault: "The galaxy obeys no one.",
    taglineNovaTerra: "Per Aspera Ad Astra.",
    taglineKharsis: "Ignis Fortem Facit.",
    subtitleDefault:
      "A persistent universe. Thousands of pilots. What empire will you build?",
    subtitleNovaTerra:
      "The Confederation needs pilots. Join Nova Terra.",
    subtitleKharsis:
      "The Dominion does not forgive. Join the Kharsis.",
    ctaPlay: "Play for free",
    ctaDiscover: "Discover the game",
    stats: [
      { value: "120+", label: "Star systems" },
      { value: "30+", label: "Ship classes" },
      { value: "18", label: "Refining recipes" },
      { value: "MMO", label: "Real-time" },
    ],
  },
  features: {
    tagline: "Your adventure starts here",
    title: "One universe.",
    titleHighlight: "Infinite possibilities.",
    subtitle:
      "Combat, exploration, trading, diplomacy — every pilot forges their own path in a galaxy shared by thousands of players.",
    cards: [
      {
        title: "Master the Void",
        subtitle:
          "Six degrees of freedom. Zero gravity. Total control.",
        description:
          "Pitch, yaw, roll, translation — every thrust matters. No rails, no limits. Newtonian flight gives you absolute control in the infinite void. Every evasive maneuver, every station approach, every pursuit is a test of pure skill.",
        stats: "6DOF  ·  Newtonian Flight  ·  Toggleable Assist",
      },
      {
        title: "Conquer by Force",
        subtitle:
          "Directional shields. Devastating weapons. Split-second decisions.",
        description:
          "Four shield faces to manage, primary and secondary weapons to alternate, energy to distribute between systems. Aim for the weak spot. Dodge torpedoes. Finish without mercy. In the void, only the most tactical survives.",
        stats:
          "4 Directional Shields  ·  Multiple Weapons  ·  Energy Management",
      },
      {
        title: "Dominate the Economy",
        subtitle:
          "Mine. Refine. Trade. Every credit counts.",
        description:
          "8 rare ores in procedural asteroid belts. 18 refining recipes. Prices that fluctuate in real-time based on supply and demand. Find the most profitable route, haul cargo through hostile systems, and build your fortune.",
        stats: "8 Ores  ·  18 Recipes  ·  Dynamic Prices",
      },
      {
        title: "Forge Alliances",
        subtitle:
          "Create a clan. Deploy your fleet. Crush your rivals.",
        description:
          "Found a clan, manage diplomacy, deploy autonomous squadrons with 5 combat roles and 5 formations. Your ships persist even when you're offline. Build an empire that shakes the galaxy.",
        stats: "Clans  ·  Squadrons  ·  Fleet Persistence",
      },
      {
        title: "Explore the Unknown",
        subtitle:
          "120+ systems. Wormholes. The vastness awaits.",
        description:
          "Jump gates, inter-galaxy wormholes, 7 star classes with unique properties. Each system has its own identity, dangers, and hidden treasures. Land on planets with unique atmospheres. Go where no one has gone before.",
        stats:
          "120+ Systems  ·  7 Star Classes  ·  Planetary Landing",
      },
      {
        title: "Write Your Legend",
        subtitle:
          "A shared universe. Thousands of pilots. Your story.",
        description:
          "Real-time synchronization, PvP combat, server-side persistent fleet. Every action impacts a galaxy shared by thousands of players. Your reputation precedes you — hero or tyrant, you decide.",
        stats: "Real-time MMO  ·  PvP  ·  Persistent Universe",
      },
    ],
  },
  faction: {
    title: "Choose your",
    titleHighlight: "side",
    backstory:
      "In 3847, united humanity colonized the galaxy under the banner of Nova Terra. Then came the Great Fracture — a cosmic cataclysm that tore known space in two. On the other side of the Rift, the forgotten colonists survived by merging with ancient alien technology. They became the Kharsis. Two civilizations. One universe.",
    choose: "Choose",
    novaTerra: {
      name: "Nova Terra",
      subtitle: "The Confederation",
      motto: "Per Aspera Ad Astra",
      description:
        "Descendants of Earth, structured and disciplined. The Nova Terra Confederation carries on the human military tradition with refined conventional technology. Powerful shields, angular hulls, surgical precision.",
      traits: [
        "Superior shields",
        "High speed",
        "Refined technology",
      ],
    },
    kharsis: {
      name: "Kharsis",
      subtitle: "The Dominion",
      motto: "Ignis Fortem Facit",
      description:
        "Colonists abandoned beyond the Rift, merged with ancient alien technology. The Kharsis Dominion evolved through force and adaptation. Devastating weapons, biomechanical hulls, raw power.",
      traits: [
        "Devastating weapons",
        "Reinforced hull",
        "Hybrid technology",
      ],
    },
  },
  ships: {
    title: "Ships",
    subtitleDefault:
      "Inspect the ships awaiting you in the Imperion universe.",
    subtitleNovaTerra:
      "The Nova Terra Confederation fleet. Precision and protection.",
    subtitleKharsis:
      "The Kharsis Dominion arsenal. Power and destruction.",
    moreShips: "More ships to discover...",
    dragHint: "Drag to rotate",
    weaponsHint: "Weapons and modules — discover in-game",
    statLabels: {
      speed: "Max speed",
      hull: "Hull",
      shields: "Shields",
    },
    defaultShips: [
      {
        name: "Fighter Mk1",
        class: "Fighter",
        description:
          "Agile and fast, the Fighter Mk1 is the backbone of any fleet. Ideal for interception and patrols.",
        statsClass: "Light fighter",
      },
      {
        name: "Frigate Mk1",
        class: "Frigate",
        description:
          "A heavy vessel designed for prolonged combat. Its multiple turrets make it a formidable adversary.",
        statsClass: "Assault frigate",
      },
    ],
    factionShips: {
      nova_terra: [
        {
          name: "Fighter NT-7",
          class: "Fighter",
          description:
            "The NT-7 embodies the Nova Terra doctrine: precision and protection. Its overpowered shields and speed make it the perfect fighter for Confederation patrols.",
          statsClass: "Line interceptor",
        },
        {
          name: "Aurora Frigate",
          class: "Frigate",
          description:
            "The Aurora Frigate is the fleet's shield. Designed to absorb and protect, its next-generation shield generators are unmatched in the galaxy.",
          statsClass: "Defense frigate",
        },
      ],
      kharsis: [
        {
          name: "Kha'ri Interceptor",
          class: "Fighter",
          description:
            "Forged beyond the Rift, the Kha'ri is a raw war machine. Its hull reinforced by alien alloys and devastating weapons more than compensate for its limited shields.",
          statsClass: "Assault fighter",
        },
        {
          name: "Kha'ri Cruiser",
          class: "Cruiser",
          description:
            "The Kha'ri Cruiser is the terror of battlefields. Its colossal mass and devastating armament make it a vessel designed for one purpose: total destruction.",
          statsClass: "Heavy cruiser",
        },
      ],
    },
  },
  universe: {
    title: "The Universe",
    subtitle:
      "A procedurally generated cosmos, connected by jump gates and inter-galaxy wormholes.",
    stats: [
      { value: "120+", label: "Star systems" },
      { value: "8", label: "Extractable ores" },
      { value: "7", label: "Star classes" },
    ],
    paragraph1:
      "Each star system has its own visual identity: stars of varied spectral classes (M, K, G, F, A, B, O), colorful nebulae, resource-rich asteroid belts and orbital stations.",
    paragraph2:
      "Navigate between systems via jump gates, or dare to cross a wormhole to reach another galaxy — hosted on a different server, with its own economy and its own players.",
  },
  server: {
    online: "online",
    offline: "offline",
    serverLabel: "Server",
    onlineLabel: "online",
    registeredLabel: "registered",
    killEvent: (actor: string, target: string) =>
      `${actor} destroyed ${target}'s ship`,
    joinEvent: (actor: string) => `${actor} joined the universe`,
    genericEvent: (actor: string) =>
      `${actor || "Someone"} — activity detected`,
  },
  screenshots: {
    title: "Preview",
    subtitle: "A few captures from the Imperion Online universe.",
    items: [
      { alt: "Space flight", caption: "Explore the vastness of outer space" },
      {
        alt: "Combat",
        caption: "Face your enemies in intense battles",
      },
      {
        alt: "Orbital station",
        caption: "Dock at stations to trade and resupply",
      },
      {
        alt: "Planetary view",
        caption: "Land on planets with unique atmospheres",
      },
      {
        alt: "Galaxy map",
        caption: "Navigate through 120+ star systems",
      },
    ],
  },
  roadmap: {
    title: "Roadmap",
    subtitle: "The journey so far and the horizons ahead.",
    statusDone: "Done",
    statusInProgress: "In Progress",
    statusUpcoming: "Upcoming",
    phases: [
      {
        title: "Space Flight",
        summary: "6DOF physics, camera, flight HUD",
        details: [
          "6 degrees of freedom ship controller",
          "3rd person camera with dynamic tracking",
          "Procedural skybox with star field",
          "Flight HUD with speed and heading indicators",
        ],
      },
      {
        title: "Procedural Universe",
        summary: "120+ systems, jump gates, galactic map",
        details: [
          "Procedural star system generation",
          "7 star classes with unique properties",
          "Jump gate and wormhole network",
          "Interactive system map and galactic map",
        ],
      },
      {
        title: "Combat",
        summary: "Weapons, directional shields, enemy AI",
        details: [
          "Combat system with primary and secondary weapons",
          "Directional shields (4 faces)",
          "Combat AI: patrol, pursuit, evasion, flee",
          "Target and lock-on system",
        ],
      },
      {
        title: "Economy & Trade",
        summary: "Stations, mining, refining, dynamic trade",
        details: [
          "8 types of extractable ores",
          "Refining system with 18 recipes",
          "Dynamic supply/demand pricing between stations",
          "Cargo system and inventory management",
        ],
      },
      {
        title: "MMO Multiplayer",
        summary: "Dedicated server, clans, fleet persistence",
        details: [
          "Real-time player and NPC synchronization",
          "Clan system with diplomacy and treasury",
          "Server-side persistent fleet deployment",
          "Squadrons with 5 roles and formations",
        ],
      },
      {
        title: "Launcher & Deployment",
        summary: "Desktop launcher, auto-update, authentication",
        details: [
          "Native launcher with authentication",
          "Automatic download and updates",
          "Go/PostgreSQL backend on Railway",
          "Integrated Discord bot",
        ],
      },
      {
        title: "3D Interiors",
        summary:
          "Explore the inside of stations and your ships",
        details: [
          "Walkable station interiors",
          "Ship bridges accessible in FPS view",
          "NPC and equipment interactions",
          "Ship cabin customization",
        ],
      },
      {
        title: "Planetary Landing",
        summary:
          "Land on planets with unique atmospheres",
        details: [
          "High-fidelity LOD planets",
          "Dynamic atmospheres per planet type",
          "Procedural vegetation and biomes",
          "Surface bases and colonies",
        ],
      },
      {
        title: "And next...",
        summary: "Something big is brewing...",
        details: [
          "New ship types and equipment",
          "Dynamic missions and events",
          "Clan territories and conquest",
          "...and much more to discover in-game",
        ],
      },
    ],
  },
  changelog: {
    title: "Changelog",
    subtitle: "The latest game updates.",
    empty: "No changelog entries yet.",
  },
  download: {
    title: "Join the adventure",
    subtitle:
      "Download the launcher, create your account and take the controls of your ship.",
    cta: "Download the launcher",
    ctaUnavailable: "Launcher coming soon",
    launcherLabel: "Launcher",
    gameLabel: "Game",
    windowsRequired: "Windows 10+ required",
  },
  auth: {
    loginTitle: "Login",
    registerTitle: "Create an account",
    accountTitle: "Account",
    username: "Username",
    email: "Email",
    password: "Password",
    confirmPassword: "Confirm",
    loginButton: "Log in",
    loginLoading: "Logging in...",
    registerButton: "Create account",
    registerLoading: "Creating...",
    logoutButton: "Logout",
    closeButton: "Close",
    noAccount: "Don't have an account?",
    createAccount: "Create an account",
    hasAccount: "Already have an account?",
    switchToLogin: "Log in",
    launcherHint: "Use the launcher to play with this account.",
    errorLogin: "Login error",
    errorRegister: "Registration error",
    errorPasswordMismatch: "Passwords do not match",
    errorPasswordLength:
      "Password must be at least 6 characters",
  },
  footer: {
    home: "Home",
    features: "Features",
    download: "Download",
  },
  notFound: {
    code: "404",
    title: "Unknown sector",
    description:
      "This area of the universe has not yet been charted.",
    backHome: "Back to home",
  },
};

export default en;
