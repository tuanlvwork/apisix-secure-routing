import { Controller, Get } from '@nestjs/common';
import { ProductsService } from './products.service';

/**
 * ROUTING ARCHITECTURE
 * ════════════════════════════════════════════════════════════════════
 *
 *  APISIX proxy-rewrite maps each port to a SEPARATE NestJS namespace:
 *
 *    Port 9080 (external, no auth)
 *      /external/*  →  /api/public/*
 *
 *    Port 9081 (internal, key-auth required)
 *      /internal/*  →  /api/internal/*
 *
 *  WHY THIS IS SECURE WITH WILDCARDS
 *  ─────────────────────────────────
 *  Both APISIX routes use wildcards (*), but the two namespaces
 *  /api/public/* and /api/internal/* never overlap.
 *
 *  Even if an attacker on port 9080 guesses a path like:
 *    GET :9080/external/internal/products   → /api/public/internal/products  → 404
 *
 *  They can never reach /api/internal/* from port 9080.
 *
 *  ADDING A NEW SERVICE — just follow the same pattern:
 *    @Controller('public/orders')   for public endpoints
 *    @Controller('internal/orders') for internal endpoints
 * ════════════════════════════════════════════════════════════════════
 */

// ── PUBLIC CONTROLLER ─────────────────────────────────────────────────────────
//   Reachable via: GET :9080/external/products
//   NestJS path:   GET /api/public/products
//   Auth:          none
// ─────────────────────────────────────────────────────────────────────────────
@Controller('public/products')
export class PublicProductsController {
  constructor(private readonly productsService: ProductsService) {}

  /** GET /api/public/products — in-stock products only */
  @Get()
  getProducts() {
    return {
      data: this.productsService.findAll(),
      meta: { visibility: 'public', timestamp: new Date().toISOString() },
    };
  }
}

// ── INTERNAL CONTROLLER ───────────────────────────────────────────────────────
//   Reachable via: GET :9081/internal/products/...   (X-API-KEY required)
//   NestJS path:   GET /api/internal/products/...
//   Auth:          APISIX key-auth (enforced before NestJS is ever called)
// ─────────────────────────────────────────────────────────────────────────────
@Controller('internal/products')
export class InternalProductsController {
  constructor(private readonly productsService: ProductsService) {}

  /** GET /api/internal/products — full inventory including out-of-stock */
  @Get()
  getProducts() {
    return {
      data: this.productsService.findAllAdmin(),
      meta: { visibility: 'internal', timestamp: new Date().toISOString() },
    };
  }

  /** GET /api/internal/products/stats — aggregate stats */
  @Get('stats')
  getStats() {
    return {
      data: this.productsService.getStats(),
      meta: { visibility: 'internal', timestamp: new Date().toISOString() },
    };
  }
}

// ── INFRA CONTROLLER ──────────────────────────────────────────────────────────
//   Health probe — not exposed through APISIX, called directly by Kubernetes
//   NestJS path: GET /api/health
// ─────────────────────────────────────────────────────────────────────────────
@Controller('health')
export class HealthController {
  /** GET /api/health — Kubernetes liveness & readiness probe */
  @Get()
  health() {
    return { status: 'ok', service: 'product-service' };
  }
}
