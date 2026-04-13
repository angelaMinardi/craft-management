export type ArchetypeId =
  | 'pattern-collector'
  | 'spontaneous-stitcher'
  | 'meticulous-maker'
  | 'social-crafter'
  | 'zen-stitcher'
  | 'adventurous-artisan';

export interface Archetype {
  id: ArchetypeId;
  name: string;
  tagline: string;
  description: string;
  color: string;
  pipExpression: string;
  ogImage: string;
}

export const ARCHETYPES: Record<ArchetypeId, Archetype> = {
  'pattern-collector': {
    id: 'pattern-collector',
    name: 'The Pattern Collector',
    tagline: 'Curator of the crafting world',
    description:
      'Your bookmarks folder is a treasure trove, your Pinterest boards could fill a library, and your "patterns to make someday" list has its own gravitational pull. You don\'t have a problem — you have a collection. Pattern Vault was literally made for you.',
    color: 'var(--dusty-blue)',
    pipExpression: 'curious',
    ogImage: '/images/og/pattern-collector.png',
  },
  'spontaneous-stitcher': {
    id: 'spontaneous-stitcher',
    name: 'The Spontaneous Stitcher',
    tagline: 'Life is too short for gauge swatches',
    description:
      'You craft on impulse, powered by enthusiasm and whatever yarn is within arm\'s reach. Your WIP pile is tall, your energy is infectious, and your creativity never sleeps. Pattern Vault will help you wrangle the beautiful chaos.',
    color: 'var(--soft-coral)',
    pipExpression: 'happy',
    ogImage: '/images/og/spontaneous-stitcher.png',
  },
  'meticulous-maker': {
    id: 'meticulous-maker',
    name: 'The Meticulous Maker',
    tagline: 'Architect of the crafting table',
    description:
      'Every project has a plan, every skein has a purpose, and your notes are works of art in themselves. You don\'t just make things — you engineer them. Pattern Vault\'s organization features will feel like coming home.',
    color: 'var(--sage-green)',
    pipExpression: 'focused',
    ogImage: '/images/og/meticulous-maker.png',
  },
  'social-crafter': {
    id: 'social-crafter',
    name: 'The Social Crafter',
    tagline: 'Crafting is your love language',
    description:
      'You stitch with friends, share discoveries with your group chat, and your happiest moments involve yarn and laughter. Your projects carry stories of the people you made them with. Pattern Vault will help you share the joy.',
    color: 'var(--honey)',
    pipExpression: 'waving',
    ogImage: '/images/og/social-crafter.png',
  },
  'zen-stitcher': {
    id: 'zen-stitcher',
    name: 'The Zen Stitcher',
    tagline: 'Meditation with a tangible result',
    description:
      'The rhythmic click of needles, the slow growth of fabric between your fingers — this is where you find peace. You don\'t rush. You don\'t scroll. You just... stitch. Pattern Vault will protect your calm.',
    color: 'var(--deep-plum)',
    pipExpression: 'sleepy',
    ogImage: '/images/og/zen-stitcher.png',
  },
  'adventurous-artisan': {
    id: 'adventurous-artisan',
    name: 'The Adventurous Artisan',
    tagline: 'Never met a technique you didn\'t want to try',
    description:
      'Tunisian crochet? Done. Brioche knitting? Mastered it last month. Fair isle with hand-spun yarn? Why not! Your craft room is a laboratory and every project is an experiment. Pattern Vault will keep track of your explorations.',
    color: 'var(--soft-coral)',
    pipExpression: 'thinking',
    ogImage: '/images/og/adventurous-artisan.png',
  },
};

export const ARCHETYPE_IDS = Object.keys(ARCHETYPES) as ArchetypeId[];

export function calculateArchetype(scores: Record<ArchetypeId, number>): ArchetypeId {
  let best: ArchetypeId = 'pattern-collector';
  let bestScore = -1;
  for (const id of ARCHETYPE_IDS) {
    if (scores[id] > bestScore) {
      bestScore = scores[id];
      best = id;
    }
  }
  return best;
}
