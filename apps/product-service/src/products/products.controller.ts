import { Controller, Get } from '@nestjs/common';
import { ProductsService } from './products.service';

/**
 * ProductsController
 *
 * With global prefix "api", effective routes are:
 *   GET /api/products          ← public list (exposed via APISIX port 9080)
 *   GET /api/products/admin    ← admin list  (exposed via APISIX port 9081 + key-auth)
 *   GET /api/products/admin/stats ← admin stats (internal only)
 *   GET /api/products/health   ← K8s liveness/readiness probe
 *
 * APISIX proxy-rewrite rules:
 *   /external/(.*) → /api/$1   (port 9080, no auth)
 *   /internal/(.*) → /api/$1   (port 9081, key-auth; 401 silently → 404)
 */
@Controller('products')
export class ProductsController {
  constructor(private readonly productsService: ProductsService) {}

  // ── PUBLIC ─────────────────────────────────────────────────────────────────

  /** GET /api/products — presented publicly on /external/products */
  @Get()
  getProducts() {
    return {
      data: this.productsService.findAll(),
      meta: { visibility: 'public', timestamp: new Date().toISOString() },
    };
  }

  // ── INTERNAL / ADMIN ───────────────────────────────────────────────────────

  /** GET /api/products/admin — full inventory including out-of-stock */
  @Get('admin')
  getAdminProducts() {
    return {
      data: this.productsService.findAllAdmin(),
      meta: { visibility: 'internal', timestamp: new Date().toISOString() },
    };
  }

  /** GET /api/products/admin/stats — aggregate stats */
  @Get('admin/stats')
  getAdminStats() {
    return {
      data: this.productsService.getStats(),
      meta: { visibility: 'internal', timestamp: new Date().toISOString() },
    };
  }

  // ── INFRA ──────────────────────────────────────────────────────────────────

  /** GET /api/products/health — Kubernetes liveness & readiness probe */
  @Get('health')
  health() {
    return { status: 'ok', service: 'product-service' };
  }
}
