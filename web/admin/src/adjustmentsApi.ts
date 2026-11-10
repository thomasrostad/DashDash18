import { supabase } from "./supabase.ts";
import { ADJUSTMENT_COLUMNS, adjustmentInsert, type Adjustment } from "./adjustments.ts";

// Tilleggspoeng (sql/072). RLS slipper bare rettigheten «tournaments» til å skrive; hver skriving
// leser raden tilbake, så en skriving RLS stoppet blir en feil og ikke en stille glipp.

/** Sesongens tilleggspoeng, eldste først. */
export async function adjustments(seasonID: string): Promise<Adjustment[]> {
  const { data, error } = await supabase.from("point_adjustments").select(ADJUSTMENT_COLUMNS)
    .eq("season_id", seasonID).order("created_at");
  if (error) throw error;
  return (data ?? []).map((r) => ({ ...r, points: Number(r.points) })) as Adjustment[];
}

export async function addAdjustment(clubID: string, seasonID: string, memberID: string, eventID: string | null, points: number, reason: string): Promise<void> {
  const { data, error } = await supabase.from("point_adjustments")
    .insert(adjustmentInsert(clubID, seasonID, memberID, eventID, points, reason)).select("id");
  if (error) throw error;
  if (!data || data.length === 0) throw new Error("Du har ikke lov til å gi tilleggspoeng.");
}

export async function deleteAdjustment(id: string): Promise<void> {
  const { data, error } = await supabase.from("point_adjustments").delete().eq("id", id).select("id");
  if (error) throw error;
  if (!data || data.length === 0) throw new Error("Fikk ikke slettet tilleggspoenget. Du har kanskje ikke lov.");
}
