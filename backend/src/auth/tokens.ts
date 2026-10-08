import { createRemoteJWKSet, jwtVerify, SignJWT, type JWTVerifyGetKey } from "jose";

const APPLE_ISSUER = "https://appleid.apple.com";
const SESSION_ISSUER = "wardrobe-backend";

/** Verifies a Sign in with Apple identity token and returns the stable Apple user id (`sub`). */
export type AppleTokenVerifier = (identityToken: string) => Promise<string>;

let appleKeys: JWTVerifyGetKey | undefined;

export function appleTokenVerifier(audiences: string[], keys?: JWTVerifyGetKey): AppleTokenVerifier {
  return async (identityToken) => {
    appleKeys ??= createRemoteJWKSet(new URL(`${APPLE_ISSUER}/auth/keys`));
    const { payload } = await jwtVerify(identityToken, keys ?? appleKeys, {
      issuer: APPLE_ISSUER,
      audience: audiences,
      algorithms: ["RS256"],
    });
    if (!payload.sub) throw new Error("Apple token has no subject");
    return payload.sub;
  };
}

export interface Session {
  token: string;
  userId: string;
  expiresAt: Date;
}

function secretKey(secret: string) {
  return new TextEncoder().encode(secret);
}

/**
 * Apple identity tokens expire after ~10 minutes, so after verifying one the backend issues its own
 * longer-lived session token (HS256). The backend stays stateless: nothing is stored.
 */
export async function issueSession(userId: string, secret: string, ttlDays: number, now = new Date()): Promise<Session> {
  const expiresAt = new Date(now.getTime() + ttlDays * 86_400_000);
  expiresAt.setMilliseconds(0);
  const token = await new SignJWT({})
    .setProtectedHeader({ alg: "HS256" })
    .setSubject(userId)
    .setIssuer(SESSION_ISSUER)
    .setIssuedAt(Math.floor(now.getTime() / 1000))
    .setExpirationTime(Math.floor(expiresAt.getTime() / 1000))
    .sign(secretKey(secret));
  return { token, userId, expiresAt };
}

export async function verifySession(token: string, secret: string): Promise<string> {
  const { payload } = await jwtVerify(token, secretKey(secret), { issuer: SESSION_ISSUER, algorithms: ["HS256"] });
  if (!payload.sub) throw new Error("Session token has no subject");
  return payload.sub;
}
