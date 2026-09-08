import "./globals.css";
import { Providers } from "./providers";
import FloatingChat from "@/components/FloatingChat";

export const metadata = {
  title: "AiMe",
  icons: {
    icon: "/favicon.ico",
    apple: "/apple-icon.png",
  },
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body>
        <Providers>
          {children}
          <FloatingChat />
        </Providers>
      </body>
    </html>
  );
}
