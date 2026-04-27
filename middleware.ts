import { NextResponse, type NextRequest } from "next/server";
import type { Session } from "@/lib/auth";

export async function middleware(request: NextRequest) {
  const { pathname } = request.nextUrl;

  const res = await fetch(new URL("/api/auth/get-session", request.nextUrl.origin), {
    headers: { cookie: request.headers.get("cookie") ?? "" },
  });
  const session: Session | null = res.ok ? await res.json() : null;

  if (pathname.startsWith("/admin")) {
    if (!session) return NextResponse.redirect(new URL("/sign-in", request.url));
    if (session.user.role !== "admin") return NextResponse.redirect(new URL("/dashboard", request.url));
    return NextResponse.next();
  }

  if (pathname.startsWith("/dashboard")) {
    if (!session) return NextResponse.redirect(new URL("/sign-in", request.url));
    return NextResponse.next();
  }

  if (pathname === "/sign-in" || pathname === "/sign-up") {
    if (session) return NextResponse.redirect(new URL("/dashboard", request.url));
    return NextResponse.next();
  }

  return NextResponse.next();
}

export const config = {
  matcher: ["/dashboard/:path*", "/admin/:path*", "/sign-in", "/sign-up"],
};
