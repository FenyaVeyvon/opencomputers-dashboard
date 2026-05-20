import {
  Body,
  Controller,
  Get,
  Headers,
  Patch,
  Param,
  Post,
  Query,
  Res,
} from '@nestjs/common';
import type { Response } from 'express';
import type { OcTelemetryDto } from './dto/oc-telemetry.dto';
import { OcService } from './oc.service';

@Controller('oc')
export class OcController {
  constructor(private readonly ocService: OcService) {}

  @Post('telemetry')
  saveTelemetry(
    @Headers('authorization') authorization: string | undefined,
    @Body() payload: OcTelemetryDto,
    @Res() response: Response,
  ) {
    if (!this.isAuthorized(authorization)) {
      return response.status(401).json({
        ok: false,
        error: 'unauthorized',
      });
    }

    return response.json(this.ocService.saveTelemetry(payload));
  }

  @Get('state')
  getState() {
    return this.ocService.getState();
  }

  @Get('nodes')
  getNodes() {
    return this.ocService.getNodes();
  }

  @Get('nodes/:node')
  getNode(@Param('node') node: string) {
    return this.ocService.getNode(node);
  }

  @Get('config')
  getConfig(@Query('node') node: string | undefined) {
    return this.ocService.getConfig(node);
  }

  @Patch('config/:node')
  updateConfig(
    @Param('node') node: string,
    @Body() payload: Record<string, unknown>,
  ) {
    return this.ocService.updateConfig(node, payload);
  }

  @Post('config/:node/reset')
  resetConfig(@Param('node') node: string) {
    return this.ocService.resetConfig(node);
  }

  @Get('health')
  getHealth() {
    return this.ocService.getHealth();
  }

  private isAuthorized(authorization: string | undefined): boolean {
    const token = process.env.OC_TOKEN ?? 'CHANGE_ME_SECRET';
    return authorization === `Bearer ${token}`;
  }
}
