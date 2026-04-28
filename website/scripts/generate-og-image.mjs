import { Resvg } from '@resvg/resvg-js';
import { readFile, writeFile } from 'node:fs/promises';
import path from 'node:path';
import satori from 'satori';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const rootDir = path.resolve(__dirname, '..', '..');
const websiteDir = path.join(rootDir, 'website');
const fontDir = path.join(rootDir, 'node_modules', '@expo-google-fonts', 'plus-jakarta-sans');
const fontPaths = [
  { weight: 400, path: path.join(fontDir, '400Regular', 'PlusJakartaSans_400Regular.ttf') },
  { weight: 500, path: path.join(fontDir, '500Medium', 'PlusJakartaSans_500Medium.ttf') },
  { weight: 600, path: path.join(fontDir, '600SemiBold', 'PlusJakartaSans_600SemiBold.ttf') },
  { weight: 700, path: path.join(fontDir, '700Bold', 'PlusJakartaSans_700Bold.ttf') },
  { weight: 800, path: path.join(fontDir, '800ExtraBold', 'PlusJakartaSans_800ExtraBold.ttf') },
];

const WIDTH = 1200;
const HEIGHT = 630;
const fontFamily = 'Plus Jakarta Sans';

function h(type, props, ...children) {
  const flatChildren = children.flat().filter((child) => child !== null && child !== undefined && child !== false);
  const nextProps = props || {};
  const hasElementChild = flatChildren.some((child) => typeof child === 'object');
  const style =
    type === 'div' && hasElementChild && !nextProps.style?.display
      ? { ...(nextProps.style || {}), display: 'flex' }
      : nextProps.style;

  return {
    type,
    props: {
      ...nextProps,
      style,
      children: flatChildren.length <= 1 ? flatChildren[0] : flatChildren,
    },
  };
}

function iconMark(size) {
  const scale = size / 42;
  const circle = (diameter, color, extra = {}) =>
    h('div', {
      style: {
        position: 'absolute',
        left: (size - diameter * scale) / 2,
        top: (size - diameter * scale) / 2,
        width: diameter * scale,
        height: diameter * scale,
        borderRadius: diameter * scale,
        backgroundColor: color,
        ...extra,
      },
    });

  return h(
    'div',
    {
      style: {
        position: 'relative',
        width: size,
        height: size,
        borderRadius: 10 * scale,
        backgroundColor: '#7DD3FC',
        display: 'flex',
        flexShrink: 0,
      },
    },
    circle(28, '#0B37C6'),
    circle(20, '#F8FAFC'),
    circle(13.2, '#38BDF8'),
    circle(6.8, '#0F172A'),
    h('div', {
      style: {
        position: 'absolute',
        left: 14.6 * scale,
        top: 10.1 * scale,
        width: 3.4 * scale,
        height: 3.4 * scale,
        borderRadius: 99,
        backgroundColor: 'rgba(255,255,255,0.72)',
      },
    })
  );
}

function statusDot(color) {
  return h('div', {
    style: {
      position: 'absolute',
      right: -4,
      bottom: -4,
      width: 13,
      height: 13,
      borderRadius: 13,
      backgroundColor: color,
      border: '3px solid #FFFFFF',
    },
  });
}

function avatar(label, bg, color, dot) {
  return h(
    'div',
    {
      style: {
        position: 'relative',
        width: 36,
        height: 36,
        borderRadius: 10,
        backgroundColor: bg,
        color,
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
        fontSize: 14,
        fontWeight: 800,
        flexShrink: 0,
      },
    },
    label,
    statusDot(dot)
  );
}

function pill(text, bg, color, width) {
  return h(
    'div',
    {
      style: {
        width,
        height: 28,
        borderRadius: 999,
        backgroundColor: bg,
        color,
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
        fontSize: 14,
        fontWeight: 750,
      },
    },
    text
  );
}

function svgIcon(size, color, children, extra = {}) {
  return h(
    'svg',
    {
      width: size,
      height: size,
      viewBox: '0 0 24 24',
      fill: 'none',
      stroke: color,
      strokeWidth: 2.2,
      strokeLinecap: 'round',
      strokeLinejoin: 'round',
      style: {
        width: size,
        height: size,
        display: 'flex',
        flexShrink: 0,
        ...extra,
      },
    },
    children
  );
}

function issueIcon(size, color) {
  return svgIcon(size, color, [
    h('path', { d: 'M12 3 2.8 20h18.4L12 3z' }),
    h('path', { d: 'M12 9v5' }),
    h('path', { d: 'M12 17h.01' }),
  ]);
}

function sortIcon(size, color) {
  return svgIcon(size, color, [
    h('path', { d: 'M8 5v14' }),
    h('path', { d: 'M5 8l3-3 3 3' }),
    h('path', { d: 'M16 19V5' }),
    h('path', { d: 'M13 16l3 3 3-3' }),
  ]);
}

function abcIcon(size, color) {
  return h(
    'div',
    {
      style: {
        width: size + 4,
        height: size,
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
        flexShrink: 0,
        color,
        fontSize: size * 0.72,
        lineHeight: 1,
        fontWeight: 760,
      },
    },
    'abc'
  );
}

function magnifyingGlass(size, color) {
  return svgIcon(size, color, [h('circle', { cx: 11, cy: 11, r: 7 }), h('path', { d: 'm21 21-4.3-4.3' })]);
}

function refreshIcon(size, color) {
  return svgIcon(size, color, [h('path', { d: 'M21 12a9 9 0 1 1-2.6-6.4' }), h('path', { d: 'M21 4v5h-5' })]);
}

function gearIcon(size, color) {
  return svgIcon(size, color, [
    h('circle', { cx: 12, cy: 12, r: 3 }),
    h('path', {
      d: 'M19.4 15a1.7 1.7 0 0 0 .3 1.8l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1.7 1.7 0 0 0-1.8-.3 1.7 1.7 0 0 0-1 1.5V21a2 2 0 1 1-4 0v-.1a1.7 1.7 0 0 0-1-1.5 1.7 1.7 0 0 0-1.8.3l-.1.1a2 2 0 1 1-2.8-2.8l.1-.1a1.7 1.7 0 0 0 .3-1.8 1.7 1.7 0 0 0-1.5-1H3a2 2 0 1 1 0-4h.1a1.7 1.7 0 0 0 1.5-1 1.7 1.7 0 0 0-.3-1.8l-.1-.1a2 2 0 1 1 2.8-2.8l.1.1a1.7 1.7 0 0 0 1.8.3h.1a1.7 1.7 0 0 0 1-1.5V3a2 2 0 1 1 4 0v.1a1.7 1.7 0 0 0 1 1.5 1.7 1.7 0 0 0 1.8-.3l.1-.1a2 2 0 1 1 2.8 2.8l-.1.1a1.7 1.7 0 0 0-.3 1.8v.1a1.7 1.7 0 0 0 1.5 1H21a2 2 0 1 1 0 4h-.1a1.7 1.7 0 0 0-1.5 1z',
    }),
  ]);
}

function row({ label, avatarText, avatarBg, avatarColor, dot, status, statusTone, muted }) {
  let statusNode;
  if (statusTone === 'degraded') statusNode = pill(status, '#FEF3C7', '#B45309', 94);
  else if (statusTone === 'outage') statusNode = pill(status, '#FFEDD5', '#9A3412', 122);
  else {
    statusNode = h(
      'div',
      {
        style: {
          fontSize: 18,
          fontWeight: 520,
          color: '#64748B',
          marginLeft: 'auto',
        },
      },
      status
    );
  }

  return h(
    'div',
    {
      style: {
        height: 48,
        padding: '0 22px',
        display: 'flex',
        alignItems: 'center',
        gap: 16,
        opacity: muted ? 0.62 : 1,
        backgroundColor: muted ? '#F8FAFC' : '#FFFFFF',
      },
    },
    avatar(avatarText, avatarBg, avatarColor, dot),
    h(
      'div',
      {
        style: {
          display: 'flex',
          alignItems: 'center',
          gap: 10,
          minWidth: 0,
          flexGrow: 1,
        },
      },
      h(
        'div',
        {
          style: {
            fontSize: 21,
            fontWeight: 720,
            color: '#0F172A',
            lineHeight: 1,
          },
        },
        label
      ),
      muted
        ? h('div', {
            style: {
              width: 14,
              height: 2,
              borderRadius: 99,
              backgroundColor: '#CBD5E1',
              transform: 'rotate(-16deg)',
            },
          })
        : null
    ),
    statusNode,
    h(
      'div',
      {
        style: {
          color: '#94A3B8',
          fontSize: 24,
          marginLeft: 10,
          lineHeight: 1,
        },
      },
      '>'
    )
  );
}

function productShot() {
  const rows = [
    {
      label: 'Claude',
      avatarText: 'CL',
      avatarBg: '#FDE4CF',
      avatarColor: '#9A3412',
      dot: '#F2C94C',
      status: 'Degraded',
      statusTone: 'degraded',
      muted: true,
    },
    {
      label: 'GitHub',
      avatarText: 'GI',
      avatarBg: '#E4E4E7',
      avatarColor: '#27272A',
      dot: '#F97316',
      status: 'Partial Outage',
      statusTone: 'outage',
    },
    {
      label: 'Asana',
      avatarText: 'AS',
      avatarBg: '#FECACA',
      avatarColor: '#991B1B',
      dot: '#22C55E',
      status: 'Operational',
      statusTone: 'ok',
    },
    {
      label: 'Figma',
      avatarText: 'FI',
      avatarBg: '#FBCFE8',
      avatarColor: '#9D174D',
      dot: '#22C55E',
      status: 'Operational',
      statusTone: 'ok',
    },
    {
      label: 'Linear',
      avatarText: 'LI',
      avatarBg: '#DDD6FE',
      avatarColor: '#5B21B6',
      dot: '#22C55E',
      status: 'Operational',
      statusTone: 'ok',
    },
    {
      label: 'Notion',
      avatarText: 'NO',
      avatarBg: '#FEF08A',
      avatarColor: '#854D0E',
      dot: '#22C55E',
      status: 'Operational',
      statusTone: 'ok',
    },
  ];

  return h(
    'div',
    {
      style: {
        position: 'absolute',
        right: 72,
        top: 112,
        width: 448,
        height: 468,
        borderRadius: 28,
        backgroundColor: '#FFFFFF',
        border: '1px solid #E2E8F0',
        boxShadow: '0 28px 70px rgba(15, 23, 42, 0.14)',
        overflow: 'hidden',
        display: 'flex',
        flexDirection: 'column',
      },
    },
    h(
      'div',
      {
        style: {
          height: 66,
          padding: '0 26px',
          display: 'flex',
          alignItems: 'center',
          borderBottom: '1px solid #E2E8F0',
          flexShrink: 0,
        },
      },
      h(
        'div',
        {
          style: {
            fontSize: 24,
            fontWeight: 780,
            color: '#0F172A',
          },
        },
        'Nazar'
      ),
      h(
        'div',
        {
          style: {
            marginLeft: 'auto',
            display: 'flex',
            alignItems: 'center',
            gap: 10,
            color: '#64748B',
            fontSize: 18,
          },
        },
        issueIcon(22, '#64748B'),
        h(
          'div',
          {
            style: {
              width: 74,
              height: 32,
              borderRadius: 9,
              border: '1px solid #E2E8F0',
              display: 'flex',
              alignItems: 'center',
              overflow: 'hidden',
            },
          },
          h(
            'div',
            {
              style: {
                width: 36,
                height: 32,
                backgroundColor: '#DCDCFD',
                color: '#4338CA',
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
              },
            },
            sortIcon(17, '#4338CA')
          ),
          h(
            'div',
            {
              style: {
                width: 37,
                height: 32,
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
              },
            },
            abcIcon(17, '#64748B')
          )
        ),
        refreshIcon(23, '#64748B'),
        gearIcon(22, '#64748B')
      )
    ),
    h(
      'div',
      {
        style: {
          height: 64,
          padding: '13px 26px 11px',
          borderBottom: '1px solid #E2E8F0',
          flexShrink: 0,
        },
      },
      h(
        'div',
        {
          style: {
            height: 40,
            borderRadius: 12,
            backgroundColor: '#F8FAFC',
            color: '#64748B',
            display: 'flex',
            alignItems: 'center',
            padding: '0 18px',
            gap: 12,
            fontSize: 20,
          },
        },
        magnifyingGlass(20, '#94A3B8'),
        'Filter services...'
      )
    ),
    h(
      'div',
      {
        style: {
          display: 'flex',
          flexDirection: 'column',
          flexGrow: 1,
        },
      },
      rows.map((service) => row(service))
    ),
    h(
      'div',
      {
        style: {
          height: 50,
          padding: '0 26px',
          borderTop: '1px solid #E2E8F0',
          backgroundColor: '#F8FAFC',
          display: 'flex',
          alignItems: 'center',
          flexShrink: 0,
        },
      },
      h('div', { style: { width: 13, height: 13, borderRadius: 13, backgroundColor: '#F97316' } }),
      h('div', { style: { marginLeft: 14, color: '#EA580C', fontSize: 20, fontWeight: 800 } }, '2 issues'),
      h('div', { style: { marginLeft: 'auto', color: '#64748B', fontSize: 18 } }, 'Updated 45 secs. ago')
    )
  );
}

function card() {
  return h(
    'div',
    {
      style: {
        width: WIDTH,
        height: HEIGHT,
        position: 'relative',
        backgroundColor: '#F4FBFF',
        fontFamily,
        overflow: 'hidden',
        display: 'flex',
      },
    },
    h(
      'div',
      {
        style: {
          position: 'absolute',
          left: 72,
          top: 66,
          display: 'flex',
          alignItems: 'center',
          gap: 16,
        },
      },
      iconMark(42),
      h('div', { style: { fontSize: 40, lineHeight: '42px', fontWeight: 720, color: '#0F172A' } }, 'Nazar')
    ),
    h(
      'div',
      {
        style: {
          position: 'absolute',
          left: 72,
          top: 174,
          display: 'flex',
          flexDirection: 'column',
          gap: 2,
        },
      },
      h('div', { style: { fontSize: 74, lineHeight: 1.08, fontWeight: 800, color: '#0F172A' } }, 'Watches the'),
      h('div', { style: { fontSize: 74, lineHeight: 1.08, fontWeight: 800, color: '#0F172A' } }, 'services you'),
      h('div', { style: { fontSize: 74, lineHeight: 1.08, fontWeight: 800, color: '#0F172A' } }, 'depend on.')
    ),
    h(
      'div',
      {
        style: {
          position: 'absolute',
          left: 76,
          top: 456,
          fontSize: 25,
          lineHeight: 1.35,
          fontWeight: 500,
          color: '#334155',
        },
      },
      'Outage alerts from your menu bar.'
    ),
    h(
      'div',
      {
        style: {
          position: 'absolute',
          left: 76,
          top: 526,
          fontSize: 21,
          color: '#64748B',
          letterSpacing: 0,
        },
      },
      'usenazar.com'
    ),
    productShot()
  );
}

const fontData = await Promise.all(
  fontPaths.map(async (font) => ({
    name: fontFamily,
    data: await readFile(font.path),
    weight: font.weight,
    style: 'normal',
  }))
);
const svg = await satori(card(), {
  width: WIDTH,
  height: HEIGHT,
  fonts: fontData,
});

await writeFile(path.join(websiteDir, 'og-image.svg'), svg);

const png = new Resvg(svg, {
  fitTo: {
    mode: 'width',
    value: WIDTH,
  },
}).render().asPng();

await writeFile(path.join(websiteDir, 'og-image.png'), png);
