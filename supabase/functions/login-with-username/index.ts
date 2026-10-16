import "@supabase/functions-js/edge-runtime.d.ts";
import { withSupabase } from "@supabase/server";

export default {
  fetch: withSupabase({ auth: ["publishable", "secret"] }, async (req, ctx) => {
    const { username, password } = await req.json();

    const { data: profile } = await ctx.supabaseAdmin
      .from("profiles")
      .select("email")
      .eq("username", username)
      .maybeSingle();

    if (!profile) {
      return Response.json({ error: "invalid_credentials" }, { status: 400 });
    }

    const { data, error } = await ctx.supabaseAdmin.auth.signInWithPassword({
      email: profile.email,
      password,
    });

    if (error) {
      return Response.json({ error: "invalid_credentials" }, { status: 400 });
    }

    return Response.json({ session: data.session, user: data.user });
  }),
};
