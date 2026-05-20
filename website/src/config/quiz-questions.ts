import type { ArchetypeId } from './archetypes';

export interface QuizAnswer {
  text: string;
  scores: Partial<Record<ArchetypeId, number>>;
}

export interface QuizQuestion {
  id: number;
  text: string;
  pipSays: string;
  answers: QuizAnswer[];
}

export const QUIZ_QUESTIONS: QuizQuestion[] = [
  {
    id: 1,
    text: "It's Saturday morning. You have the whole day free. What do you reach for first?",
    pipSays: "Ooh, a free day! Let's see what kind of crafter you are...",
    answers: [
      { text: 'My phone — time to browse for new patterns', scores: { 'pattern-collector': 2 } },
      { text: 'Whatever yarn is closest — let\'s just start!', scores: { 'spontaneous-stitcher': 2 } },
      { text: 'My project notebook — I need to review my plan', scores: { 'meticulous-maker': 2 } },
      { text: 'My group chat — who wants to craft together?', scores: { 'social-crafter': 2 } },
      { text: 'My current WIP — time to zone out and stitch', scores: { 'zen-stitcher': 2 } },
      { text: 'A tutorial for a technique I\'ve never tried', scores: { 'adventurous-artisan': 2 } },
    ],
  },
  {
    id: 2,
    text: 'You find an amazing pattern online. What happens next?',
    pipSays: 'I find at least 12 amazing patterns a day. No judgement here.',
    answers: [
      { text: 'Save it to my 400-pattern wishlist. I\'ll get to it... eventually', scores: { 'pattern-collector': 2 } },
      { text: 'Buy the yarn immediately and cast on tonight', scores: { 'spontaneous-stitcher': 2 } },
      { text: 'Add it to a spreadsheet with yarn requirements and timeline', scores: { 'meticulous-maker': 2, 'pattern-collector': 1 } },
      { text: 'Share it in three group chats and tag two friends', scores: { 'social-crafter': 2 } },
      { text: 'Bookmark it quietly. When the time is right, I\'ll know', scores: { 'zen-stitcher': 2 } },
      { text: 'Start thinking about how I\'d modify it', scores: { 'adventurous-artisan': 2 } },
    ],
  },
  {
    id: 3,
    text: 'Your yarn stash is best described as...',
    pipSays: 'No judgement on stash size. I promise.',
    answers: [
      { text: 'Organized by weight, color, and fiber content', scores: { 'meticulous-maker': 2 } },
      { text: 'Overflowing and I regret nothing', scores: { 'pattern-collector': 2, 'spontaneous-stitcher': 1 } },
      { text: 'Curated — every skein has a purpose', scores: { 'zen-stitcher': 2 } },
      { text: 'Half of it was bought on craft-along hauls with friends', scores: { 'social-crafter': 2 } },
      { text: 'Constantly rotating — I buy for the project I\'m about to start', scores: { 'spontaneous-stitcher': 2 } },
      { text: 'Full of experimental fibers and unusual materials', scores: { 'adventurous-artisan': 2 } },
    ],
  },
  {
    id: 4,
    text: 'When following a pattern, you typically...',
    pipSays: 'There are no wrong answers here. Okay, maybe one. (Just kidding.)',
    answers: [
      { text: 'Follow it exactly as written, checking gauge twice', scores: { 'meticulous-maker': 2 } },
      { text: 'Use it as a rough guide and improvise freely', scores: { 'spontaneous-stitcher': 2, 'adventurous-artisan': 1 } },
      { text: 'Make detailed notes on every modification', scores: { 'meticulous-maker': 2, 'pattern-collector': 1 } },
      { text: 'Follow along with a video tutorial while chatting', scores: { 'social-crafter': 2 } },
      { text: 'Let the rhythm of the stitches guide me', scores: { 'zen-stitcher': 2 } },
      { text: 'Combine elements from three different patterns', scores: { 'adventurous-artisan': 2 } },
    ],
  },
  {
    id: 5,
    text: "What's your biggest crafting frustration?",
    pipSays: 'Vent to me. I\'m a very good listener. *tilts head*',
    answers: [
      { text: 'I can never find that pattern I saved three months ago', scores: { 'pattern-collector': 2 } },
      { text: 'I have twelve WIPs and zero finished objects', scores: { 'spontaneous-stitcher': 2 } },
      { text: "When the finished piece doesn't match the swatch", scores: { 'meticulous-maker': 2 } },
      { text: "Crafting alone — it's more fun with people", scores: { 'social-crafter': 2 } },
      { text: "Interruptions when I'm finally in the zone", scores: { 'zen-stitcher': 2 } },
      { text: 'Running out of new techniques to learn', scores: { 'adventurous-artisan': 2 } },
    ],
  },
  {
    id: 6,
    text: 'You just finished a project. Your first instinct is to...',
    pipSays: 'Finished?! That deserves a celebration!',
    answers: [
      { text: 'Photograph it beautifully and add it to my project log', scores: { 'meticulous-maker': 2, 'pattern-collector': 1 } },
      { text: 'Immediately start something new', scores: { 'spontaneous-stitcher': 2 } },
      { text: 'Post it everywhere and tag the designer', scores: { 'social-crafter': 2 } },
      { text: 'Sit with it for a moment and appreciate the calm', scores: { 'zen-stitcher': 2 } },
      { text: "Think about what I'd do differently next time", scores: { 'adventurous-artisan': 2 } },
      { text: 'Add the pattern to my "completed" folder (it joins the other 3)', scores: { 'pattern-collector': 2 } },
    ],
  },
  {
    id: 7,
    text: 'A magical crow offers you one crafting superpower. You pick...',
    pipSays: 'Choose wisely! (Or don\'t. I won\'t judge.)',
    answers: [
      { text: 'Instant pattern recall — never lose a saved pattern again', scores: { 'pattern-collector': 2 } },
      { text: 'Infinite motivation — every project gets finished', scores: { 'spontaneous-stitcher': 2 } },
      { text: 'Perfect tension — every stitch identical', scores: { 'meticulous-maker': 2 } },
      { text: 'Teleportation — craft with any friend, anywhere', scores: { 'social-crafter': 2 } },
      { text: 'Time freeze — endless uninterrupted crafting hours', scores: { 'zen-stitcher': 2 } },
      { text: 'Instant mastery of any technique you see', scores: { 'adventurous-artisan': 2 } },
    ],
  },
];
