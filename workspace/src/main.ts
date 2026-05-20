import { NestFactory } from '@nestjs/core';
import { RequestMethod } from '@nestjs/common';
import { json } from 'express';
import { AppModule } from './app.module';

async function bootstrap() {
  const app = await NestFactory.create(AppModule);
  app.setGlobalPrefix('api', {
    exclude: [{ path: '/', method: RequestMethod.GET }],
  });
  app.enableCors({
    origin: [
      'https://open.eonhorizon.net',
      'http://localhost:3000',
      'http://localhost:5173',
      'http://localhost:5174',
    ],
  });
  app.use(json({ limit: '1mb' }));
  await app.listen(process.env.PORT ?? 4444);
}
void bootstrap();
