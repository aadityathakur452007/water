export type JsonObject = string | number | boolean | null | JsonObject[] | { [key: string]: JsonObject };

export type WorkerEnvelope = {
  data?: JsonObject[];
  next_cursor?: string;
  [key: string]: JsonObject | string | undefined;
};

export class WorkerApiError extends Error {
  status: number;
  code: string;
  traceId: string;

  constructor(status: number, code: string, message: string, traceId = "") {
    super(message);
    this.status = status;
    this.code = code;
    this.traceId = traceId;
  }
}

export type RoleLoginResult = { ok: true; role: string } | { ok: false; status: number; code: string; message: string };
