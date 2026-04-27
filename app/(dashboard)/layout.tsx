import Link from "next/link";
import { redirect } from "next/navigation";
import { headers } from "next/headers";
import { auth } from "@/lib/auth";

const navLinks = [
  { href: "/dashboard", label: "My Pets" },
  { href: "/explore", label: "Explore" },
  { href: "/notifications", label: "Notifications" },
];

const DEV_SESSION = {
  user: { id: "dev-user", name: "Dev User", email: "dev@local.dev", role: "admin" as const },
  session: { id: "dev-session", userId: "dev-user" },
};

export default async function DashboardLayout({ children }: { children: React.ReactNode }) {
  const session =
    process.env.NODE_ENV === "development"
      ? ((await auth.api.getSession({ headers: await headers() })) ?? DEV_SESSION)
      : await auth.api.getSession({ headers: await headers() });

  if (!session) redirect("/sign-in");

  const isAdmin = session.user.role === "admin";

  return (
    <div className="flex min-h-screen">
      <aside className="w-56 shrink-0 border-r border-border flex flex-col bg-card">
        <div className="p-6 border-b border-border">
          <Link href="/dashboard" className="font-display text-lg font-semibold">
            PetAI
          </Link>
        </div>

        <nav className="flex-1 p-4 space-y-1">
          {navLinks.map((link) => (
            <Link
              key={link.href}
              href={link.href}
              className="flex items-center px-3 py-2 rounded-md text-sm text-muted-foreground hover:text-foreground hover:bg-secondary transition-colors"
            >
              {link.label}
            </Link>
          ))}

          {isAdmin && (
            <>
              <div className="pt-4 pb-1 px-3">
                <span className="text-xs font-medium text-muted-foreground uppercase tracking-wider">Admin</span>
              </div>
              <Link
                href="/admin"
                className="flex items-center px-3 py-2 rounded-md text-sm text-muted-foreground hover:text-foreground hover:bg-secondary transition-colors"
              >
                Chaos Dashboard
              </Link>
              <Link
                href="/admin/species"
                className="flex items-center px-3 py-2 rounded-md text-sm text-muted-foreground hover:text-foreground hover:bg-secondary transition-colors"
              >
                Species
              </Link>
              <Link
                href="/admin/moderation"
                className="flex items-center px-3 py-2 rounded-md text-sm text-muted-foreground hover:text-foreground hover:bg-secondary transition-colors"
              >
                Moderation
              </Link>
            </>
          )}
        </nav>

        <div className="p-4 border-t border-border">
          <p className="text-xs text-muted-foreground truncate">{session.user.email}</p>
        </div>
      </aside>

      <main className="flex-1 min-w-0 p-8">
        {children}
      </main>
    </div>
  );
}
