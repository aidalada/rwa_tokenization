import { Providers } from './providers';

export const metadata = {
  title: 'RWA Tokenization Platform DAO',
  description: 'Full-stack DeFi App for RWA Assets',
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="ru">
      <body style={{ margin: 0, padding: 0, backgroundColor: '#0f172a' }}>
        <Providers>{children}</Providers>
      </body>
    </html>
  );
}