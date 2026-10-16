-- Safe leaderboard refresh: updates read-only ranking functions only.
-- Does not alter, delete, or rewrite profiles, quizzes, sessions, questions, or scores.

BEGIN;

CREATE OR REPLACE FUNCTION public.leaderboard(
  p_mode text DEFAULT 'quiz',
  p_quiz text DEFAULT NULL,
  p_period text DEFAULT 'week'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  local_day date := (now() AT TIME ZONE 'Asia/Tbilisi')::date;
  cutoff date;
BEGIN
  cutoff := CASE
    WHEN p_period = 'month' THEN date_trunc('month', local_day)::date
    WHEN p_period = 'day' THEN local_day
    ELSE date_trunc('week', local_day)::date
  END;

  RETURN COALESCE((
    SELECT jsonb_agg(to_jsonb(r))
    FROM (
      SELECT p.nickname,
             round(avg(s.score::numeric / NULLIF(jsonb_array_length(s.items), 0)), 1) AS points,
             count(*)::int AS rounds
      FROM public.sessions AS s
      JOIN public.profiles AS p ON p.id = s.user_id
      WHERE s.mode = p_mode
        AND s.finished_at IS NOT NULL
        AND s.cursor > 0
        AND (p_mode <> 'daily' OR s.day >= cutoff)
        AND (p_quiz IS NULL OR s.quiz_id = p_quiz)
      GROUP BY p.id, p.nickname
      ORDER BY points DESC, rounds DESC, p.nickname, p.id
      LIMIT 50
    ) AS r
  ), '[]'::jsonb);
END;
$$;

CREATE OR REPLACE FUNCTION public.leaderboard_theme(p_theme text)
RETURNS jsonb
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE(jsonb_agg(to_jsonb(r)), '[]'::jsonb)
  FROM (
    SELECT p.nickname,
           round(avg(s.score::numeric / NULLIF(jsonb_array_length(s.items), 0)), 1) AS points,
           count(*)::int AS rounds
    FROM public.sessions AS s
    JOIN public.profiles AS p ON p.id = s.user_id
    JOIN public.quizzes AS q ON q.id = s.quiz_id
    WHERE s.mode = 'quiz'
      AND s.finished_at IS NOT NULL
      AND s.cursor > 0
      AND q.theme = p_theme
    GROUP BY p.id, p.nickname
    ORDER BY points DESC, rounds DESC, p.nickname, p.id
    LIMIT 50
  ) AS r;
$$;

REVOKE ALL ON FUNCTION public.leaderboard(text, text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.leaderboard_theme(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.leaderboard(text, text, text) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.leaderboard_theme(text) TO anon, authenticated;

COMMIT;
