import { Body, Controller, Get, Param, Patch, Post, Query } from '@nestjs/common';
import { ApiService } from './api.service';

@Controller('api')
export class ApiController {
  constructor(private readonly api: ApiService) {}

  @Get('nodes')
  getNodes() {
    return this.api.getNodes();
  }

  @Get('health')
  getHealth() {
    return { ok: true, service: 'eonlink', time: Date.now() };
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

  @Post('nodes/:node/rpc')
  async rpc(
    @Param('node') node: string,
    @Body()
    body: {
      t?: string;
      token?: string;
      level?: string;
      message?: string;
    },
  ) {
    if (body.t === 'log') {
      await this.api.writeLog(node, body.level || 'info', body.message || '');
    } else if (body.t === 'chat_message') {
      await this.api.writeLog(node, 'chat', body.message || '');
    }
    return this.api.getConfig(node, body.token);
  }
}
