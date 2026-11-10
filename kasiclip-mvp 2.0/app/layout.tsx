import type { Metadata } from 'next';
import './globals.css';
export const metadata: Metadata = {
  title: 'KasiClip — Creator Campaign Platform',
  description: 'Clipping platform and brand campaign management. By KasiFakta, supported by KasiMediaGroup.',
};
export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return <html lang="id"><body>{children}</body></html>;
}
