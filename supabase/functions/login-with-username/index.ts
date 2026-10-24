import "@supabase/functions-js/edge-runtime.d.ts";
import { withSupabase } from "@supabase/server";

export default {
  fetch: withSupabase({ auth: ["publishable", "secret"] }, async (req, ctx) => {
    const body = await req.json().catch(() => ({}));
    const username = typeof body.username === "string" ? body.username.trim() : "";
    const password = typeof body.password === "string" ? body.password : "";

    if (!username || !password) {
      return Response.json({ error: "invalid_credentials" }, { status: 400 });
    }

    // Case-insensitive lookup (usernames are unique on lower(username)).
    // The SQL function is executable by the service role only, so client
    // roles can never read profiles.email through it.
    const { data: email, error: lookupError } = await ctx.supabaseAdmin
      .rpc("username_email", { uname: username });

    if (lookupError || !email) {
      return Response.json({ error: "invalid_credentials" }, { status: 400 });
    }

    const { data, error } = await ctx.supabaseAdmin.auth.signInWithPassword({
      email,
      password,
    });

    if (error) {
      return Response.json({ error: "invalid_credentials" }, { status: 400 });
    }

    return Response.json({ session: data.session, user: data.user });
  }),
};
