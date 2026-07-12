// Tiny hand-rolled router — no framework. The route set here is small and
// fixed (six endpoints, see src/index.ts), so this deliberately does not
// try to be a general-purpose routing library: exact method+path matching
// only, generic over the `Env` type so `src/index.ts` gets full type
// safety on handler parameters without this file needing to know what
// `Env` looks like.

export interface RouteContext<AppEnv> {
  request: Request;
  env: AppEnv;
  execCtx: ExecutionContext;
}

export type RouteHandler<AppEnv> = (ctx: RouteContext<AppEnv>) => Promise<Response> | Response;

interface Route<AppEnv> {
  method: string;
  path: string;
  handler: RouteHandler<AppEnv>;
}

function normalizePath(path: string): string {
  if (path.length > 1 && path.endsWith("/")) return path.slice(0, -1);
  return path;
}

export class Router<AppEnv> {
  private readonly routes: Route<AppEnv>[] = [];

  add(method: string, path: string, handler: RouteHandler<AppEnv>): this {
    this.routes.push({ method: method.toUpperCase(), path: normalizePath(path), handler });
    return this;
  }

  get(path: string, handler: RouteHandler<AppEnv>): this {
    return this.add("GET", path, handler);
  }

  post(path: string, handler: RouteHandler<AppEnv>): this {
    return this.add("POST", path, handler);
  }

  /** Finds the handler for a method+pathname, or `undefined` if nothing matches. Exposed separately from `handle` so tests can assert on routing decisions without constructing a full `Env`. */
  match(method: string, pathname: string): RouteHandler<AppEnv> | undefined {
    const normalized = normalizePath(pathname);
    const upperMethod = method.toUpperCase();
    return this.routes.find((route) => route.method === upperMethod && route.path === normalized)?.handler;
  }

  /** Routes a request, or returns `null` if no route matches (callers turn that into a 404). */
  async handle(request: Request, env: AppEnv, execCtx: ExecutionContext): Promise<Response | null> {
    const url = new URL(request.url);
    const handler = this.match(request.method, url.pathname);
    if (!handler) return null;
    return handler({ request, env, execCtx });
  }
}
