import { Injectable, Logger, OnModuleInit } from '@nestjs/common';
import { createServer, Socket } from 'net';
import { ApiService } from './api.service';

@Injectable()
export class TcpGateway implements OnModuleInit {
  private readonly logger = new Logger(TcpGateway.name);

  constructor(private readonly api: ApiService) {}

  onModuleInit() {
    const port = Number(process.env.EONLINK_TCP_PORT ?? 4445);
    createServer((socket) => this.handle(socket)).listen(port, () => {
      this.logger.log(`EonLink TCP JSON listening on ${port}`);
    });
  }

  private handle(socket: Socket) {
    let buffer = '';
    socket.on('data', (chunk) => {
      buffer += chunk.toString('utf8');
      while (buffer.includes('\n')) {
        const index = buffer.indexOf('\n');
        const line = buffer.slice(0, index).trim();
        buffer = buffer.slice(index + 1);
        if (line) void this.handleLine(socket, line);
      }
    });
  }

  private async handleLine(socket: Socket, line: string) {
    try {
      const msg = JSON.parse(line) as {
        t?: string;
        node?: string;
        token?: string;
        level?: string;
        message?: string;
      };
      const node = msg.node || 'base_pc_1';
      if (msg.t === 'hello' || msg.t === 'config_get') {
        socket.write(
          JSON.stringify(await this.api.getConfig(node, msg.token)) + '\n',
        );
      } else if (msg.t === 'log') {
        await this.api.writeLog(node, msg.level || 'info', msg.message || '');
      }
    } catch (error) {
      socket.write(JSON.stringify({ t: 'error', message: String(error) }) + '\n');
    }
  }
}
