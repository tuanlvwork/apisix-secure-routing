import { NestFactory } from '@nestjs/core';
import { AppModule } from './app.module';

async function bootstrap() {
  const app = await NestFactory.create(AppModule);

  // Global prefix — APISIX proxy-rewrite strips /external|internal/ leaving /api/...
  app.setGlobalPrefix('api');

  const port = process.env.PORT ?? 3000;
  await app.listen(port);
  console.log(`[product-service] Listening on port ${port}`);
}

bootstrap();
