import { Body, Controller, Get, Param, Patch, Query } from '@nestjs/common';
import { ApiService } from './api.service';

@Controller('api')
export class ApiController {
  constructor(private readonly api: ApiService) {}

  @Get('nodes')
  getNodes() {
    return this.api.getNodes();
  }

  @Get('nodes/:node')
  getNode(@Param('node') node: string) {
    return this.api.getNode(node);
  }

  @Get('nodes/:node/config')
  getConfig(@Param('node') node: string, @Query('token') token?: string) {
    return this.api.getConfig(node, token);
  }

  @Patch('nodes/:node/config')
  updateConfig(
    @Param('node') node: string,
    @Body() body: { label?: string; token?: string; members?: string[] },
  ) {
    return this.api.updateConfig(node, body);
  }

  @Get('nodes/:node/logs')
  getLogs(@Param('node') node: string) {
    return this.api.getLogs(node);
  }
}
