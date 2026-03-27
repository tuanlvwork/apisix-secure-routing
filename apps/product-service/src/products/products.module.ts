import { Module } from '@nestjs/common';
import {
  PublicProductsController,
  InternalProductsController,
  HealthController,
} from './products.controller';
import { ProductsService } from './products.service';

@Module({
  controllers: [
    PublicProductsController,
    InternalProductsController,
    HealthController,
  ],
  providers: [ProductsService],
})
export class ProductsModule {}
