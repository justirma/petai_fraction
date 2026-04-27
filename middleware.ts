import { auth } from "@/lib/auth";
import { type NextRequest, NextResponse } from "next/server";

export async function middleware(request: NextRequest) {
  const { pathname } = request.nextUrl;

  const session = await auth.api.getSession({ headers: request.headers });

  if (pathname.startsWith("/admin")) {
    if (!session) return NextResponse.redirect(new URL("/sign-in", request.url));
    if (session.user.role !== "admin")
      return NextResponse.redirect(new URL("/dashboard", request.url));
    return NextResponse.next();
  }

  if (
    pathname.startsWith("/dashboard") ||
    pathname.startsWith("/explore") ||
    pathname.startsWith("/notifications")
  ) {
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
  runtime: "nodejs",
  matcher: ["/dashboard/:path*", "/admin/:path*", "/explore/:path*", "/notifications/:path*", "/sign-in", "/sign-up"],
};
