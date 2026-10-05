import * as React from "react";

import { useAdminQuery } from "./use-admin-api";
import type { Page } from "@/lib/admin-types";

/**
 * Cursor-follow paging over a server-paginated admin list: page 1 loads,
 * "Load more" appends the next cursor page. Counts shown from `rows.length`
 * are labeled loaded-rows, never totals — the server owns totals.
 */
export function useCursorPages<T>(basePath: string) {
  const [cursor, setCursor] = React.useState("");
  const [rows, setRows] = React.useState<T[]>([]);
  const path = cursor
    ? `${basePath}${basePath.includes("?") ? "&" : "?"}cursor=${encodeURIComponent(cursor)}`
    : basePath;
  const query = useAdminQuery<Page<T>>(path);
  const seenRef = React.useRef("");

  // New filter set → drop accumulated rows and restart from page 1.
  React.useEffect(() => {
    setCursor("");
    setRows([]);
    seenRef.current = "";
  }, [basePath]);

  React.useEffect(() => {
    if (!query.data) return;
    const key = `${basePath}|${cursor}`;
    if (seenRef.current === key) return;
    seenRef.current = key;
    const page = query.data.data ?? [];
    setRows((prev) => (cursor === "" ? page : [...prev, ...page]));
  }, [query.data, basePath, cursor]);

  return {
    rows,
    nextCursor: query.data?.next_cursor ?? "",
    isFetching: query.isFetching,
    isError: query.isError,
    error: query.error,
    loadMore: () => {
      const next = query.data?.next_cursor ?? "";
      if (next) setCursor(next);
    },
  };
}
