import { Injectable, UnauthorizedException } from '@nestjs/common';
import { PrismaService } from '../prisma.service';

const DEFAULT_TOKEN = process.env.EONLINK_NODE_TOKEN ?? 'change-me';

@Injectable()
export class ApiService {
  constructor(private readonly prisma: PrismaService) {}

  async ensureNode(id: string) {
    return this.prisma.node.upsert({
      where: { id },
      update: {},
      create: {
        id,
        label: id,
        token: DEFAULT_TOKEN,
      },
      include: { members: true },
    });
  }

  async getNodes() {
    return this.prisma.node.findMany({
      include: { members: true },
      orderBy: { id: 'asc' },
    });
  }

  async getNode(id: string) {
    return this.ensureNode(id);
  }

  async getConfig(id: string, token?: string) {
    const node = await this.ensureNode(id);
    this.assertToken(node.token, token);
    return {
      t: 'config',
      node: node.id,
      nodeLabel: node.label,
      configVersion: node.configVersion,
      members: node.members.map((member) => member.name),
    };
  }

  async updateConfig(
    id: string,
    body: { label?: string; token?: string; members?: string[] },
  ) {
    await this.ensureNode(id);
    const data: {
      label?: string;
      token?: string;
      configVersion: { increment: 1 };
    } = {
      configVersion: { increment: 1 },
    };
    if (typeof body.label === 'string') data.label = body.label;
    if (typeof body.token === 'string') data.token = body.token;

    await this.prisma.$transaction([
      this.prisma.node.update({ where: { id }, data }),
      ...(Array.isArray(body.members)
        ? [
            this.prisma.member.deleteMany({ where: { nodeId: id } }),
            this.prisma.member.createMany({
              data: body.members.map((name) => ({ nodeId: id, name })),
              skipDuplicates: true,
            }),
          ]
        : []),
    ]);

    return this.getNode(id);
  }

  async writeLog(id: string, level: string, message: string) {
    await this.ensureNode(id);
    return this.prisma.log.create({
      data: { nodeId: id, level: level || 'info', message: message || '' },
    });
  }

  async getLogs(id: string) {
    return this.prisma.log.findMany({
      where: { nodeId: id },
      orderBy: { createdAt: 'desc' },
      take: 100,
    });
  }

  private assertToken(expected: string, actual?: string) {
    if (actual !== expected) throw new UnauthorizedException('bad node token');
  }
}
