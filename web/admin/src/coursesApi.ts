import { supabase } from "./supabase.ts";
import { deleteErrorText, saveErrorText, saveParams, type CourseHoleRow, type CourseKind, type CourseRow, type CourseValues } from "./courses.ts";

// Klubbens baner (sql/002, 016). Krever retten «Runder og føring» (courses_*-policyene og save_course, sql/044).

const COLUMNS = "id, club_id, name, external_name, course_rating, slope_rating, in_use, kind";

export async function clubCourses(clubID: string): Promise<{ courses: CourseRow[]; holes: CourseHoleRow[] }> {
  const { data, error } = await supabase.from("courses").select(COLUMNS).eq("club_id", clubID);
  if (error) throw error;
  const courses = (data as CourseRow[]).sort((a, b) => a.name.localeCompare(b.name, "nb"));
  if (courses.length === 0) return { courses, holes: [] };
  const h = await supabase.from("course_holes").select("course_id, hole_number, par, stroke_index, length_m").in("course_id", courses.map((c) => c.id));
  if (h.error) throw h.error;
  return { courses, holes: h.data as CourseHoleRow[] };
}

/** Lagrer banen og alle hullene i én transaksjon (`save_course`), så typen (som `save_course` ikke kjenner).
 *  Sjekker at hullene kom tilbake, som appen. Gir id-en. */
export async function saveCourse(clubID: string, courseID: string | null, v: CourseValues): Promise<string> {
  const { data, error } = await supabase.rpc("save_course", saveParams(clubID, courseID, v));
  if (error) throw new Error(saveErrorText(error, v.name));
  const id = data as string;
  await saveKind(id, v.kind);
  const h = await supabase.from("course_holes").select("hole_number").eq("course_id", id);
  if (h.error) throw h.error;
  if ((h.data ?? []).length !== v.holes.length) throw new Error("Banen ble ikke lagret slik den sto. Last inn på nytt og sjekk.");
  return id;
}

async function saveKind(id: string, kind: CourseKind): Promise<void> {
  const { data, error } = await supabase.from("courses").update({ kind }).eq("id", id).select("id");
  if (error) throw error;
  if (!data || data.length === 0) throw new Error("Du har ikke tilgang til å endre banen.");
}

/** Sletter banen og hullene. Databasen stopper det når runder bruker banen. */
export async function deleteCourse(id: string): Promise<void> {
  const { data, error } = await supabase.from("courses").delete().eq("id", id).select("id");
  if (error) throw new Error(deleteErrorText(error));
  if (!data || data.length === 0) throw new Error("Du har ikke tilgang til å slette banen.");
}
