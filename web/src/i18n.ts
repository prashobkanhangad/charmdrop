export const locales = ["en", "hi", "es"] as const;
export type Locale = (typeof locales)[number];

export const localeMeta: Record<
  Locale,
  { label: string; htmlLang: string; dir: "ltr" | "rtl" }
> = {
  en: { label: "EN", htmlLang: "en", dir: "ltr" },
  hi: { label: "हिन्दी", htmlLang: "hi", dir: "ltr" },
  es: { label: "ES", htmlLang: "es", dir: "ltr" },
};

export function pathFor(locale: Locale, path = "/"): string {
  const normalized = path.startsWith("/") ? path : `/${path}`;
  const clean = normalized === "/" ? "" : normalized;
  return locale === "en" ? clean || "/" : `/${locale}${clean}`;
}

export function switchLocale(pathname: string, next: Locale): string {
  const stripped = pathname.replace(/^\/(hi|es)(?=\/|$)/, "") || "/";
  return pathFor(next, stripped);
}

export function copy(locale: Locale) {
  return dictionary[locale];
}

const dictionary = {
  en: {
    title: "CharmDrop — a lucky charm for your Mac",
    description:
      "A native macOS menu bar app that hangs a lucky charm from the top of your screen. Grab the rope, flick it, and keep working. Nothing leaves your Mac.",
    nav: {
      features: "Features",
      charms: "Charms",
      buy: "Download",
    },
    hero: {
      eyebrow: "Native macOS · menu bar",
      heading: "A lucky charm that hangs from your Mac.",
      body: "Pull the rope. Flick it. It settles above your work and stays out of the way — click-through everywhere except the charm itself.",
      buy: "Download CharmDrop",
      try: "Drag the charm — this is the real physics.",
      requirement: "macOS 14 Sonoma or later · Apple Silicon",
    },
    features: {
      heading: "Built like a Mac app, not a web wrapper.",
      items: [
        {
          title: "Real rope physics",
          body: "A Verlet simulation, not a GIF. Grab, stretch, and flick. It swings, then comes to rest.",
        },
        {
          title: "Click-through desktop",
          body: "The overlay covers the display but ignores the pointer unless you are on the charm.",
        },
        {
          title: "Rituals, not gimmicks",
          body: "Click to hang a fresh Nimbu Mirchi, light a Diya, ring the bell, or wake the Nazar.",
        },
        {
          title: "Private by design",
          body: "No account, no analytics, no network. Preferences stay on this Mac.",
        },
        {
          title: "Lives in the menu bar",
          body: "No Dock icon while you work. Launch at login when you want it waiting at the bezel.",
        },
        {
          title: "Yours to place",
          body: "Left, centre, right, or a custom spot. Length, thickness, and size are yours.",
        },
      ],
    },
    charms: {
      heading: "Four charms. Same rope.",
      body: "Tap a charm to hang it on the stage above. In the app, a click starts its ritual.",
      items: [
        {
          id: "nimbu-mirchi",
          name: "Nimbu Mirchi",
          ritual: "Replace",
          body: "Lemon and chillies on a thread. Click to hang a fresh one.",
        },
        {
          id: "nazar",
          name: "Nazar",
          ritual: "Pulse",
          body: "A blue eye for the desktop. Click to make it glow.",
        },
        {
          id: "bell",
          name: "Temple Bell",
          ritual: "Swing",
          body: "Brass, slightly inharmonic. Click to ring it.",
        },
        {
          id: "diya",
          name: "Diya",
          ritual: "Toggle",
          body: "An oil lamp. Click to light it; the flame keeps flickering.",
        },
      ],
    },
    pricing: {
      heading: "Hang one on your Mac.",
      body: "Free. Version 0.1.0. Download the DMG — drag it into Applications, then open it from the menu bar.",
      free: "Free",
      download: "Download CharmDrop.dmg",
      coffee: "Buy me a coffee",
      support:
        "The app is free on every Mac. If CharmDrop made you smile, you can buy me a coffee.",
      note: "Ad-hoc signed build for now — Gatekeeper may ask you to open it from the context menu until we notarize.",
    },
    thanks: {
      pageTitle: "Download — CharmDrop",
      heading: "Grab the DMG.",
      body: "Download the app, drag it into Applications, then open CharmDrop from the menu bar.",
      download: "Download CharmDrop.dmg",
      coffee: "Buy me a coffee",
      back: "Back to CharmDrop",
    },
    privacy: {
      nav: "Privacy",
      heading: "Nothing leaves the machine.",
      body: "CharmDrop needs no account and makes no network requests. It does not read your files, keystrokes, or screen. The pointer is sampled only to decide whether it is over the charm.",
      payment:
        "CharmDrop is free to download. Optional support on this site goes through Buy Me a Coffee. The Mac app itself stays offline.",
      pageTitle: "Privacy — CharmDrop",
    },
    footer: {
      tagline: "A small native thing, hanging from the top of the screen.",
    },
  },
  hi: {
    title: "CharmDrop — आपके Mac का शुभ चार्म",
    description:
      "एक नेटिव macOS मेनू बार ऐप, जो स्क्रीन के ऊपरी किनारे से एक शुभ चार्म लटकाता है। रस्सी खींचें, झटका दें, और काम करते रहें। कुछ भी आपके Mac से बाहर नहीं जाता।",
    nav: {
      features: "ख़ासियतें",
      charms: "चार्म",
      buy: "डाउनलोड",
    },
    hero: {
      eyebrow: "नेटिव macOS · मेनू बार",
      heading: "एक शुभ चार्म, आपके Mac से लटका हुआ।",
      body: "रस्सी खींचें। झटका दें। यह आपके काम के ऊपर बैठ जाता है और रास्ते में नहीं आता — चार्म के अलावा सब कुछ क्लिक-थ्रू है।",
      buy: "CharmDrop डाउनलोड करें",
      try: "चार्म को खींचकर देखें — यही असली भौतिकी है।",
      requirement: "macOS 14 सोनोमा या उससे नया · Apple Silicon",
    },
    features: {
      heading: "वेब रैपर नहीं, असली Mac ऐप।",
      items: [
        {
          title: "असली रस्सी की भौतिकी",
          body: "GIF नहीं, Verlet सिमुलेशन। पकड़ें, खींचें, झटका दें। झूले, फिर रुक जाए।",
        },
        {
          title: "क्लिक-थ्रू डेस्कटॉप",
          body: "ओवरले पूरी स्क्रीन ढकता है, पर पॉइंटर तभी पकड़ता है जब आप चार्म पर हों।",
        },
        {
          title: "रीति, तमाशा नहीं",
          body: "ताज़ा नींबू-मिर्ची टाँगें, दिया जलाएँ, घंटी बजाएँ, या नज़र जगाएँ।",
        },
        {
          title: "गोपनीयता डिज़ाइन में है",
          body: "कोई खाता नहीं, कोई एनालिटिक्स नहीं, कोई नेटवर्क नहीं। सेटिंग्स यहीं रहती हैं।",
        },
        {
          title: "मेनू बार में रहता है",
          body: "काम करते समय Dock आइकन नहीं। चाहें तो लॉगिन पर अपने आप खुले।",
        },
        {
          title: "जहाँ चाहें टाँगें",
          body: "बाएँ, बीच, दाएँ, या अपनी जगह। लंबाई, मोटाई और आकार आपके हाथ में।",
        },
      ],
    },
    charms: {
      heading: "चार चार्म। एक ही रस्सी।",
      body: "ऊपर के मंच पर लटकाने के लिए एक चार्म चुनें। ऐप में क्लिक से उसकी रीति चलती है।",
      items: [
        {
          id: "nimbu-mirchi",
          name: "नींबू मिर्ची",
          ritual: "बदलें",
          body: "धागे पर नींबू और मिर्च। क्लिक करें, ताज़ा लटक जाए।",
        },
        {
          id: "nazar",
          name: "नज़र",
          ritual: "चमक",
          body: "डेस्कटॉप के लिए नीली आँख। क्लिक करें, चमक उठे।",
        },
        {
          id: "bell",
          name: "मंदिर घंटी",
          ritual: "झूलन",
          body: "पीतल की, थोड़ी अनहार्मोनिक। क्लिक करें, बज उठे।",
        },
        {
          id: "diya",
          name: "दिया",
          ritual: "जलाना",
          body: "तेल का दीपक। क्लिक करें, जले; लौ टिमटिमाती रहे।",
        },
      ],
    },
    pricing: {
      heading: "अपने Mac पर एक टाँगें।",
      body: "मुफ़्त। संस्करण 0.1.0। DMG डाउनलोड करें — उसे Applications में खींचें, फिर मेनू बार से खोलें।",
      free: "मुफ़्त",
      download: "CharmDrop.dmg डाउनलोड करें",
      coffee: "मुझे कॉफ़ी पिलाएँ",
      support:
        "ऐप हर Mac पर मुफ़्त है। अगर CharmDrop ने मुस्कान दी, तो एक कॉफ़ी पिला सकते हैं।",
      note: "अभी ऐड-हॉक साइन है — नोटरीज़ होने तक Gatekeeper संदर्भ मेनू से खोलने को कह सकता है।",
    },
    thanks: {
      pageTitle: "डाउनलोड — CharmDrop",
      heading: "DMG ले जाएँ।",
      body: "ऐप डाउनलोड करें, Applications में खींचें, फिर मेनू बार से CharmDrop खोलें।",
      download: "CharmDrop.dmg डाउनलोड करें",
      coffee: "मुझे कॉफ़ी पिलाएँ",
      back: "CharmDrop पर वापस",
    },
    privacy: {
      nav: "गोपनीयता",
      heading: "कुछ भी मशीन से बाहर नहीं जाता।",
      body: "CharmDrop को खाते की ज़रूरत नहीं, और यह नेटवर्क से नहीं जुड़ता। यह आपकी फ़ाइलें, कुंजियाँ या स्क्रीन नहीं पढ़ता। पॉइंटर केवल यह जानने के लिए देखा जाता है कि वह चार्म पर है या नहीं।",
      payment:
        "CharmDrop मुफ़्त डाउनलोड है। इस साइट पर वैकल्पिक सहयोग Buy Me a Coffee से जाता है। Mac ऐप ऑफ़लाइन ही रहता है।",
      pageTitle: "गोपनीयता — CharmDrop",
    },
    footer: {
      tagline: "एक छोटी नेटिव चीज़, स्क्रीन के ऊपरी किनारे से लटकी हुई।",
    },
  },
  es: {
    title: "CharmDrop — un amuleto para tu Mac",
    description:
      "Una app nativa de la barra de menús de macOS que cuelga un amuleto de la suerte del borde superior de la pantalla. Tira de la cuerda, lánzalo y sigue trabajando. Nada sale de tu Mac.",
    nav: {
      features: "Funciones",
      charms: "Amuletos",
      buy: "Descargar",
    },
    hero: {
      eyebrow: "macOS nativo · barra de menús",
      heading: "Un amuleto de la suerte que cuelga de tu Mac.",
      body: "Tira de la cuerda. Lánzalo. Se queda sobre tu trabajo y no estorba: todo es click-through salvo el amuleto.",
      buy: "Descargar CharmDrop",
      try: "Arrastra el amuleto: esta es la física de verdad.",
      requirement: "macOS 14 Sonoma o posterior · Apple Silicon",
    },
    features: {
      heading: "Hecha como una app de Mac, no como una web envuelta.",
      items: [
        {
          title: "Física real de cuerda",
          body: "Una simulación Verlet, no un GIF. Agarra, estira y lanza. Se balancea y se detiene.",
        },
        {
          title: "Escritorio click-through",
          body: "La capa cubre la pantalla, pero ignora el puntero salvo cuando está sobre el amuleto.",
        },
        {
          title: "Rituales, no adornos",
          body: "Cuelga un Nimbu Mirchi fresco, enciende un Diya, toca la campana o despierta el Nazar.",
        },
        {
          title: "Privada por diseño",
          body: "Sin cuenta, sin analítica, sin red. Las preferencias se quedan en este Mac.",
        },
        {
          title: "Vive en la barra de menús",
          body: "Sin icono en el Dock mientras trabajas. Ábrela al iniciar sesión si quieres.",
        },
        {
          title: "Tú eliges el sitio",
          body: "Izquierda, centro, derecha o un punto propio. Largo, grosor y tamaño son tuyos.",
        },
      ],
    },
    charms: {
      heading: "Cuatro amuletos. La misma cuerda.",
      body: "Elige un amuleto para colgarlo arriba. En la app, un clic inicia su ritual.",
      items: [
        {
          id: "nimbu-mirchi",
          name: "Nimbu Mirchi",
          ritual: "Reemplazar",
          body: "Limón y chiles en un hilo. Clic para colgar uno fresco.",
        },
        {
          id: "nazar",
          name: "Nazar",
          ritual: "Pulso",
          body: "Un ojo azul para el escritorio. Clic para que brille.",
        },
        {
          id: "bell",
          name: "Campana",
          ritual: "Balanceo",
          body: "Latón, un poco inarmónica. Clic para hacerla sonar.",
        },
        {
          id: "diya",
          name: "Diya",
          ritual: "Encender",
          body: "Una lámpara de aceite. Clic para encenderla; la llama titila.",
        },
      ],
    },
    pricing: {
      heading: "Cuelga uno en tu Mac.",
      body: "Gratis. Versión 0.1.0. Descarga el DMG: arrástralo a Applications y ábrelo desde la barra de menús.",
      free: "Gratis",
      download: "Descargar CharmDrop.dmg",
      coffee: "Invítame un café",
      support:
        "La app es gratis en cualquier Mac. Si CharmDrop te arrancó una sonrisa, puedes invitarme un café.",
      note: "Firma ad hoc por ahora: Gatekeeper puede pedirte que la abras desde el menú contextual hasta que la notariemos.",
    },
    thanks: {
      pageTitle: "Descargar — CharmDrop",
      heading: "Llévate el DMG.",
      body: "Descarga la app, arrástrala a Applications y abre CharmDrop desde la barra de menús.",
      download: "Descargar CharmDrop.dmg",
      coffee: "Invítame un café",
      back: "Volver a CharmDrop",
    },
    privacy: {
      nav: "Privacidad",
      heading: "Nada sale de la máquina.",
      body: "CharmDrop no pide cuenta ni hace peticiones de red. No lee tus archivos, teclas ni pantalla. El puntero solo se usa para saber si está sobre el amuleto.",
      payment:
        "CharmDrop se descarga gratis. El apoyo opcional en este sitio va por Buy Me a Coffee. La app de Mac sigue sin conexión.",
      pageTitle: "Privacidad — CharmDrop",
    },
    footer: {
      tagline: "Una cosa nativa y pequeña, colgada del borde de la pantalla.",
    },
  },
} as const;
