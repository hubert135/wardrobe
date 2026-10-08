// Vercel entry point (Edge runtime). vercel.json routes every path here.
import { handle } from "hono/vercel";
import { createAppFromEnv } from "../src/env.js";

export const config = { runtime: "edge" };

export default handle(createAppFromEnv(process.env));
