import localFont from "next/font/local";

export const rajdhani = localFont({
  src: [
    { path: "../../public/fonts/Rajdhani-Regular.ttf", weight: "400", style: "normal" },
    { path: "../../public/fonts/Rajdhani-Medium.ttf", weight: "500", style: "normal" },
    { path: "../../public/fonts/Rajdhani-Bold.ttf", weight: "700", style: "normal" },
  ],
  variable: "--font-heading",
  display: "swap",
});

export const shareTechMono = localFont({
  src: [{ path: "../../public/fonts/ShareTechMono-Regular.ttf", weight: "400", style: "normal" }],
  variable: "--font-mono",
  display: "swap",
});
