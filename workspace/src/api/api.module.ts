import { Module } from '@nestjs/common';
import { PrismaService } from '../prisma.service';
import { ApiController } from './api.controller';
import { ApiService } from './api.service';
import { TcpGateway } from './tcp.gateway';

@Module({
  controllers: [ApiController],
  providers: [ApiService, PrismaService, TcpGateway],
})
export class ApiModule {}
