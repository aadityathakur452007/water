"use client";

/**
 * DataTable — the one data-grid primitive (TanStack Table v9).
 * Gives every admin table: click-to-sort headers (aria-sort), a column-visibility
 * menu, and CSV export of the loaded page (server paging is cursor-based, so the
 * export honestly covers the shown rows). Pages keep their own empty/loading/error
 * wrappers — this renders the grid itself.
 *
 * v9 note: features are registered explicitly (rowSortingFeature +
 * columnVisibilityFeature + sorted row-model factory) on a static feature set;
 * pages build typed columns via `columnHelper<T>()`.
 */
import { useState } from "react";
import {
  columnVisibilityFeature,
  createColumnHelper,
  createSortedRowModel,
  flexRender,
  rowSortingFeature,
  tableFeatures,
  useTable,
  type ColumnDef,
  type ColumnVisibilityState,
  type SortingState,
} from "@tanstack/react-table";
import { ArrowDown, ArrowUp, Columns3, Download } from "lucide-react";

/** One static feature set for every admin grid (stable identity → stable models). */
const gridFeatures = tableFeatures({
  rowSortingFeature,
  columnVisibilityFeature,
  sortedRowModel: createSortedRowModel(),
});

/** Typed column builder — call at module scope per page: `const helper = columnHelper<UserRow>()`. */
export function columnHelper<T extends object>() {
  return createColumnHelper<typeof gridFeatures, T>();
}

export type GridColumns<T extends object> = ReadonlyArray<ColumnDef<typeof gridFeatures, T>>;

function csvEscape(value: string | number | null): string {
  const s = value === null || value === undefined ? "" : String(value);
  return /[",\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
}

export function DataTable<T extends object>({
  columns,
  data,
  csvFilename,
  csv,
}: {
  columns: GridColumns<T>;
  data: T[];
  /** Enables the CSV button; exports the loaded rows in the current sort order. */
  csvFilename?: string;
  /** Flat columns for CSV export (badges/links export as their flat value). */
  csv?: { label: string; value: (row: T) => string | number | null }[];
}) {
  const [sorting, setSorting] = useState<SortingState>([]);
  const [columnVisibility, setColumnVisibility] = useState<ColumnVisibilityState>({});

  const table = useTable({
    features: gridFeatures,
    columns,
    data,
    state: { sorting, columnVisibility },
    onSortingChange: setSorting,
    onColumnVisibilityChange: setColumnVisibility,
  });

  const hideable = table.getAllLeafColumns().filter((c) => c.getCanHide());

  function exportCsv() {
    if (!csv || csv.length === 0) return;
    const lines = [csv.map((c) => csvEscape(c.label))];
    for (const row of table.getRowModel().rows) {
      lines.push(csv.map((c) => csvEscape(c.value(row.original))));
    }
    // BOM so Excel opens ₹/UTF-8 correctly.
    const blob = new Blob(["\uFEFF" + lines.map((l) => l.join(",")).join("\r\n")], {
      type: "text/csv;charset=utf-8",
    });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = csvFilename ?? "export.csv";
    a.click();
    URL.revokeObjectURL(url);
  }

  return (
    <div>
      {(csvFilename || hideable.length > 1) && (
        <div className="flex items-center justify-end gap-2 border-b border-line-soft px-5 py-2">
          {csvFilename && csv ? (
            <button
              type="button"
              onClick={exportCsv}
              className="inline-flex h-7 items-center gap-1.5 rounded-md border border-line px-2.5 text-xs font-medium text-steel transition-colors hover:bg-canvas hover:text-ink"
            >
              <Download className="size-3.5" aria-hidden />
              CSV
            </button>
          ) : null}
          {hideable.length > 1 ? (
            <details className="relative">
              <summary className="inline-flex h-7 cursor-pointer list-none items-center gap-1.5 rounded-md border border-line px-2.5 text-xs font-medium text-steel transition-colors hover:bg-canvas hover:text-ink [&::-webkit-details-marker]:hidden">
                <Columns3 className="size-3.5" aria-hidden />
                Columns
              </summary>
              <div className="absolute right-0 z-10 mt-1 w-48 rounded-xl border border-line bg-surface p-1.5 shadow-card">
                {hideable.map((c) => {
                  const label =
                    typeof c.columnDef.header === "string" ? c.columnDef.header : c.id;
                  return (
                    <label
                      key={c.id}
                      className="flex cursor-pointer items-center gap-2 rounded-lg px-2.5 py-1.5 text-xs text-ink transition-colors hover:bg-canvas"
                    >
                      <input
                        type="checkbox"
                        checked={c.getIsVisible()}
                        onChange={(e) => c.toggleVisibility(e.target.checked)}
                        className="size-3.5 accent-[var(--color-accent)]"
                      />
                      {label}
                    </label>
                  );
                })}
              </div>
            </details>
          ) : null}
        </div>
      )}
      <div className="overflow-x-auto">
        <table className="w-full text-sm">
          <thead>
            {table.getHeaderGroups().map((hg) => (
              <tr
                key={hg.id}
                className="border-b border-line text-left text-[11px] uppercase tracking-wide text-steel"
              >
                {hg.headers.map((h) => {
                  const sorted = h.column.getIsSorted();
                  const label = h.isPlaceholder
                    ? null
                    : flexRender(h.column.columnDef.header, h.getContext());
                  return (
                    <th
                      key={h.id}
                      aria-sort={
                        sorted === "asc" ? "ascending" : sorted === "desc" ? "descending" : undefined
                      }
                      className="px-3 py-2.5 font-medium first:px-5 last:px-5"
                    >
                      {h.column.getCanSort() ? (
                        <button
                          type="button"
                          onClick={h.column.getToggleSortingHandler()}
                          className="inline-flex items-center gap-1 uppercase tracking-wide transition-colors hover:text-ink"
                        >
                          {label}
                          {sorted === "asc" ? (
                            <ArrowUp className="size-3" aria-hidden />
                          ) : sorted === "desc" ? (
                            <ArrowDown className="size-3" aria-hidden />
                          ) : null}
                        </button>
                      ) : (
                        label
                      )}
                    </th>
                  );
                })}
              </tr>
            ))}
          </thead>
          <tbody className="divide-y divide-line-soft">
            {table.getRowModel().rows.map((row) => (
              <tr key={row.id} className="transition-colors hover:bg-canvas">
                {row.getVisibleCells().map((cell) => (
                  <td key={cell.id} className="px-3 py-3 first:px-5 last:px-5">
                    {flexRender(cell.column.columnDef.cell, cell.getContext())}
                  </td>
                ))}
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}
