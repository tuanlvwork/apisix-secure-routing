import { Injectable } from '@nestjs/common';

export interface Product {
  id: number;
  name: string;
  price: number;
  inStock: boolean;
}

@Injectable()
export class ProductsService {
  private readonly products: Product[] = [
    { id: 1, name: 'Widget Alpha', price: 9.99, inStock: true },
    { id: 2, name: 'Gadget Beta', price: 24.99, inStock: true },
    { id: 3, name: 'Device Gamma', price: 49.99, inStock: false },
  ];

  /** Public-safe: only in-stock products */
  findAll(): Product[] {
    return this.products.filter((p) => p.inStock);
  }

  /** Admin: all products regardless of stock */
  findAllAdmin(): Product[] {
    return this.products;
  }

  /** Admin: aggregated stats */
  getStats() {
    const total = this.products.length;
    const inStock = this.products.filter((p) => p.inStock).length;
    return {
      total,
      inStock,
      outOfStock: total - inStock,
      avgPrice:
        this.products.reduce((s, p) => s + p.price, 0) / total,
    };
  }
}
