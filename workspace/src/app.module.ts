import { Module } from '@nestjs/common';
import { AppController } from './app.controller';
import { AppService } from './app.service';
import { OcModule } from './oc/oc.module';

@Module({
  imports: [OcModule],
  controllers: [AppController],
  providers: [AppService],
})
export class AppModule {}
