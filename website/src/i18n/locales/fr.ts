import type { Translations } from "..";

const fr: Translations = {
  meta: {
    description:
      "La galaxie n'obéit à personne. MMORPG spatial en monde ouvert — explorez, combattez, conquérez.",
  },
  nav: {
    home: "Accueil",
    features: "Features",
    ships: "Vaisseaux",
    universe: "Univers",
    roadmap: "Roadmap",
    download: "Télécharger",
    login: "Connexion",
    logout: "Deconnexion",
    changeFaction: "Changer de faction",
    resetFaction: "Rechoisir (afficher selecteur)",
  },
  hero: {
    badge: "Alpha 0.1 — Accès anticipé",
    taglineDefault: "La galaxie n'obéit à personne.",
    taglineNovaTerra: "Per Aspera Ad Astra.",
    taglineKharsis: "Ignis Fortem Facit.",
    subtitleDefault:
      "Un univers persistant. Des milliers de pilotes. Quel empire allez-vous bâtir ?",
    subtitleNovaTerra:
      "La Confédération a besoin de pilotes. Rejoignez Nova Terra.",
    subtitleKharsis:
      "Le Dominion ne pardonne pas. Rejoignez le Kharsis.",
    ctaPlay: "Jouer gratuitement",
    ctaDiscover: "Découvrir le jeu",
    stats: [
      { value: "120+", label: "Systèmes stellaires" },
      { value: "30+", label: "Classes de vaisseaux" },
      { value: "18", label: "Recettes de raffinage" },
      { value: "MMO", label: "Temps réel" },
    ],
  },
  features: {
    tagline: "Votre aventure commence ici",
    title: "Un seul univers.",
    titleHighlight: "Infinies possibilités.",
    subtitle:
      "Combat, exploration, commerce, diplomatie — chaque pilote forge son propre chemin dans une galaxie partagée par des milliers de joueurs.",
    cards: [
      {
        title: "Maîtrisez le Vide",
        subtitle:
          "Six degrés de liberté. Zéro gravité. Contrôle total.",
        description:
          "Tangage, lacet, roulis, translation — chaque impulsion compte. Pas de rails, pas de limites. Le vol Newtonien vous donne un contrôle absolu dans le vide infini. Chaque manoeuvre d'évasion, chaque approche de station, chaque poursuite est un test de skill pur.",
        stats: "6DOF  ·  Vol Newtonien  ·  Assistance désactivable",
      },
      {
        title: "Conquérez par les Armes",
        subtitle:
          "Boucliers directionnels. Armes dévastatrices. Décisions en une fraction de seconde.",
        description:
          "Quatre faces de bouclier à gérer, des armes primaires et secondaires à alterner, de l'énergie à répartir entre systèmes. Visez le point faible. Esquivez les torpilles. Achevez sans pitié. Dans le vide, seul le plus tactique survit.",
        stats:
          "4 boucliers directionnels  ·  Armes multiples  ·  Gestion d'énergie",
      },
      {
        title: "Dominez l'Économie",
        subtitle:
          "Minez. Raffinez. Commercez. Chaque crédit compte.",
        description:
          "8 minerais rares dans des ceintures d'astéroïdes procédurales. 18 recettes de raffinage. Des prix qui fluctuent en temps réel selon l'offre et la demande. Trouvez la route la plus rentable, transportez du cargo à travers des systèmes hostiles, et bâtissez votre fortune.",
        stats: "8 minerais  ·  18 recettes  ·  Prix dynamiques",
      },
      {
        title: "Forgez des Alliances",
        subtitle:
          "Créez un clan. Déployez votre flotte. Écrasez vos rivaux.",
        description:
          "Fondez un clan, gérez la diplomatie, déployez des escadrons autonomes avec 5 rôles de combat et 5 formations. Vos vaisseaux persistent même quand vous êtes hors-ligne. Construisez un empire qui fait trembler la galaxie.",
        stats: "Clans  ·  Escadrons  ·  Persistance de flotte",
      },
      {
        title: "Explorez l'Inconnu",
        subtitle:
          "120+ systèmes. Des wormholes. L'immensité vous attend.",
        description:
          "Jump gates, wormholes inter-galaxies, 7 classes d'étoiles aux propriétés uniques. Chaque système a son identité, ses dangers, ses trésors cachés. Posez-vous sur des planètes aux atmosphères uniques. Allez là où personne n'est encore allé.",
        stats:
          "120+ systèmes  ·  7 classes d'étoiles  ·  Atterrissage planétaire",
      },
      {
        title: "Écrivez Votre Légende",
        subtitle:
          "Un univers partagé. Des milliers de pilotes. Votre histoire.",
        description:
          "Synchronisation temps réel, combats PvP, flotte persistante côté serveur. Chaque action impacte une galaxie partagée par des milliers de joueurs. Votre réputation vous précède — héros ou tyran, c'est vous qui décidez.",
        stats: "MMO temps réel  ·  PvP  ·  Univers persistant",
      },
    ],
  },
  faction: {
    title: "Choisissez votre",
    titleHighlight: "camp",
    backstory:
      "En 3847, l'humanite unie colonisait la galaxie sous la banniere de Nova Terra. Puis vint la Grande Fracture \u2014 un cataclysme cosmique qui dechira l'espace connu en deux. De l'autre cote du Rift, les colons oublies ont survecu en fusionnant avec une technologie alien ancestrale. Ils sont devenus le Kharsis. Deux civilisations. Un seul univers.",
    choose: "Choisir",
    novaTerra: {
      name: "Nova Terra",
      subtitle: "La Confederation",
      motto: "Per Aspera Ad Astra",
      description:
        "Descendants de la Terre, structures et disciplins. La Confederation Nova Terra perpuee la tradition militaire humaine avec une technologie conventionnelle raffinee. Boucliers puissants, coques angulaires, precision chirurgicale.",
      traits: [
        "Boucliers superieurs",
        "Vitesse elevee",
        "Technologie raffinee",
      ],
    },
    kharsis: {
      name: "Kharsis",
      subtitle: "Le Dominion",
      motto: "Ignis Fortem Facit",
      description:
        "Colons abandonnes au-dela du Rift, fusionnes avec une technologie alien ancestrale. Le Dominion Kharsis a evolue par la force et l'adaptation. Armes devastatrices, coques biomechaniques, puissance brute.",
      traits: [
        "Armes devastatrices",
        "Coque renforcee",
        "Technologie hybride",
      ],
    },
  },
  ships: {
    title: "Vaisseaux",
    subtitleDefault:
      "Inspectez les vaisseaux qui vous attendent dans l'univers d'Imperion.",
    subtitleNovaTerra:
      "La flotte de la Confédération Nova Terra. Précision et protection.",
    subtitleKharsis:
      "L'arsenal du Dominion Kharsis. Puissance et destruction.",
    moreShips: "Plus de vaisseaux à découvrir...",
    dragHint: "Glisser pour tourner",
    weaponsHint: "Armement et modules — à découvrir en jeu",
    statLabels: {
      speed: "Vitesse max",
      hull: "Coque",
      shields: "Boucliers",
    },
    defaultShips: [
      {
        name: "Fighter Mk1",
        class: "Chasseur",
        description:
          "Agile et rapide, le Fighter Mk1 est l'épine dorsale de toute flotte. Idéal pour l'interception et les patrouilles.",
        statsClass: "Chasseur léger",
      },
      {
        name: "Frigate Mk1",
        class: "Frégate",
        description:
          "Un vaisseau lourd conçu pour le combat prolongé. Ses tourelles multiples en font un adversaire redoutable.",
        statsClass: "Frégate d'assaut",
      },
    ],
    factionShips: {
      nova_terra: [
        {
          name: "Fighter NT-7",
          class: "Chasseur",
          description:
            "Le NT-7 incarne la doctrine Nova Terra : précision et protection. Ses boucliers surpuissants et sa vitesse en font le chasseur parfait pour les patrouilles de la Confédération.",
          statsClass: "Intercepteur de ligne",
        },
        {
          name: "Frégate Aurore",
          class: "Frégate",
          description:
            "La Frégate Aurore est le bouclier de la flotte. Conçue pour encaisser et protéger, ses générateurs de boucliers de dernière génération sont inégalés dans la galaxie.",
          statsClass: "Frégate de défense",
        },
      ],
      kharsis: [
        {
          name: "Intercepteur Kha'ri",
          class: "Chasseur",
          description:
            "Forgé au-delà du Rift, le Kha'ri est une machine de guerre brute. Sa coque renforcée par des alliages aliens et ses armes dévastatrices compensent largement ses boucliers limités.",
          statsClass: "Chasseur d'assaut",
        },
        {
          name: "Croiseur Kha'ri",
          class: "Croiseur",
          description:
            "Le Croiseur Kha'ri est la terreur des champs de bataille. Sa masse colossale et son armement dévastateur en font un vaisseau conçu pour un seul objectif : la destruction totale.",
          statsClass: "Croiseur lourd",
        },
      ],
    },
  },
  universe: {
    title: "L'Univers",
    subtitle:
      "Un cosmos généré procéduralement, relié par des jump gates et des wormholes inter-galaxies.",
    stats: [
      { value: "120+", label: "Systèmes stellaires" },
      { value: "8", label: "Minerais extractibles" },
      { value: "7", label: "Classes d'étoiles" },
    ],
    paragraph1:
      "Chaque système stellaire possède sa propre identité visuelle : étoiles de classes spectrales variées (M, K, G, F, A, B, O), nébuleuses colorées, ceintures d'astéroïdes riches en ressources et stations orbitales.",
    paragraph2:
      "Naviguez entre les systèmes via les jump gates, ou osez traverser un wormhole pour rejoindre une autre galaxie — hébergée sur un serveur différent, avec sa propre économie et ses propres joueurs.",
  },
  server: {
    online: "en ligne",
    offline: "hors ligne",
    serverLabel: "Serveur",
    onlineLabel: "en ligne",
    registeredLabel: "inscrits",
    killEvent: (actor: string, target: string) =>
      `${actor} a détruit le vaisseau de ${target}`,
    joinEvent: (actor: string) => `${actor} a rejoint l'univers`,
    genericEvent: (actor: string) =>
      `${actor || "Quelqu'un"} — activité détectée`,
  },
  screenshots: {
    title: "Aperçu",
    subtitle: "Quelques captures de l'univers d'Imperion Online.",
    items: [
      { alt: "Vol spatial", caption: "Explorez l'immensité du vide spatial" },
      {
        alt: "Combat",
        caption: "Affrontez vos ennemis dans des combats intenses",
      },
      {
        alt: "Station orbitale",
        caption:
          "Amarrez-vous aux stations pour commercer et vous ravitailler",
      },
      {
        alt: "Vue planétaire",
        caption:
          "Atterrissez sur des planètes aux atmosphères uniques",
      },
      {
        alt: "Galaxy map",
        caption: "Naviguez à travers 120+ systèmes stellaires",
      },
    ],
  },
  roadmap: {
    title: "Roadmap",
    subtitle: "Le chemin parcouru et les horizons à venir.",
    statusDone: "Terminé",
    statusInProgress: "En cours",
    statusUpcoming: "À venir",
    phases: [
      {
        title: "Vol spatial",
        summary: "Physique 6DOF, caméra, HUD de pilotage",
        details: [
          "Contrôleur de vaisseau 6 degrés de liberté",
          "Caméra 3e personne avec suivi dynamique",
          "Skybox procédural avec champ d'étoiles",
          "HUD de pilotage avec indicateurs de vitesse et cap",
        ],
      },
      {
        title: "Univers procédural",
        summary: "120+ systèmes, jump gates, carte galactique",
        details: [
          "Génération procédurale de systèmes stellaires",
          "7 classes d'étoiles avec propriétés uniques",
          "Réseau de jump gates et wormholes",
          "Carte du système et carte galactique interactives",
        ],
      },
      {
        title: "Combat",
        summary: "Armes, boucliers directionnels, IA ennemie",
        details: [
          "Système de combat avec armes primaires et secondaires",
          "Boucliers directionnels (4 faces)",
          "IA de combat : patrouille, poursuite, évasion, fuite",
          "Système de cible et verrouillage",
        ],
      },
      {
        title: "Économie & Commerce",
        summary: "Stations, minage, raffinage, commerce dynamique",
        details: [
          "8 types de minerais extractibles",
          "Système de raffinage avec 18 recettes",
          "Prix dynamiques offre/demande entre stations",
          "Système de cargo et gestion d'inventaire",
        ],
      },
      {
        title: "Multijoueur MMO",
        summary: "Serveur dédié, clans, persistence de flotte",
        details: [
          "Synchronisation temps réel des joueurs et PNJ",
          "Système de clans avec diplomatie et trésorerie",
          "Déploiement de flotte persistant côté serveur",
          "Escadrons avec 5 rôles et formations",
        ],
      },
      {
        title: "Launcher & Déploiement",
        summary: "Launcher desktop, auto-update, authentification",
        details: [
          "Launcher natif avec authentification",
          "Téléchargement et mise à jour automatique",
          "Backend Go/PostgreSQL sur Railway",
          "Bot Discord intégré",
        ],
      },
      {
        title: "Intérieurs 3D",
        summary:
          "Explorez l'intérieur des stations et de vos vaisseaux",
        details: [
          "Intérieurs de stations visitables à pied",
          "Ponts de vaisseaux accessibles en vue FPS",
          "Interactions avec les PNJ et les équipements",
          "Personnalisation des cabines de vaisseau",
        ],
      },
      {
        title: "Atterrissage planétaire",
        summary:
          "Posez-vous sur des planètes aux atmosphères uniques",
        details: [
          "Planètes avec LOD haute fidélité",
          "Atmosphères dynamiques par type de planète",
          "Végétation et biomes procéduraux",
          "Bases et colonies en surface",
        ],
      },
      {
        title: "Et ensuite...",
        summary: "Quelque chose de grand se prépare...",
        details: [
          "Nouveaux types de vaisseaux et équipements",
          "Missions et événements dynamiques",
          "Territoires de clan et conquête",
          "...et bien plus à découvrir en jeu",
        ],
      },
    ],
  },
  changelog: {
    title: "Changelog",
    subtitle: "Les dernières mises à jour du jeu.",
    empty: "Aucune entrée de changelog pour le moment.",
  },
  download: {
    title: "Rejoignez l'aventure",
    subtitle:
      "Téléchargez le launcher, créez votre compte et prenez les commandes de votre vaisseau.",
    cta: "Télécharger le launcher",
    ctaUnavailable: "Launcher bientôt disponible",
    launcherLabel: "Launcher",
    gameLabel: "Jeu",
    windowsRequired: "Windows 10+ requis",
  },
  auth: {
    loginTitle: "Connexion",
    registerTitle: "Créer un compte",
    accountTitle: "Compte",
    username: "Identifiant",
    email: "Email",
    password: "Mot de passe",
    confirmPassword: "Confirmer",
    loginButton: "Se connecter",
    loginLoading: "Connexion...",
    registerButton: "Créer le compte",
    registerLoading: "Création...",
    logoutButton: "Déconnexion",
    closeButton: "Fermer",
    noAccount: "Pas encore de compte ?",
    createAccount: "Créer un compte",
    hasAccount: "Déjà un compte ?",
    switchToLogin: "Se connecter",
    launcherHint: "Utilisez le launcher pour jouer avec ce compte.",
    errorLogin: "Erreur de connexion",
    errorRegister: "Erreur lors de l'inscription",
    errorPasswordMismatch: "Les mots de passe ne correspondent pas",
    errorPasswordLength:
      "Le mot de passe doit faire au moins 6 caractères",
  },
  footer: {
    home: "Accueil",
    features: "Features",
    download: "Télécharger",
  },
  notFound: {
    code: "404",
    title: "Secteur inconnu",
    description:
      "Cette zone de l'univers n'a pas encore été cartographiée.",
    backHome: "Retour à l'accueil",
  },
};

export default fr;
