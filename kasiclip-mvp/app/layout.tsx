import type { Metadata } from 'next';
import './globals.css';
export const metadata: Metadata = { title: 'KasiClip | Creator Campaign Platform', description: 'Platform distribusi campaign berbasis performa creator.' };
export default function RootLayout({ children }: Readonly<{children: React.ReactNode}>) { return <html lang="id"><body>{children}</body></html>; }
