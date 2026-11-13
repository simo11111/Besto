import { describe, expect, it } from 'vitest';
import { splitHauntedAnnouncementText } from './hauntedAudio';

describe('Haunted narrator text chunking', () => {
  it('preserves every word and punctuation mark in long Darija narration', () => {
    const text = 'هبط الليل على المخيم، والناس كاملين كيتسناو شنو غادي يوقع. آ المسكون، اختار لاعب واحد فالسر، ومن بعد غادي يجي دور الفقيه باش يختار شكون يحمي.';
    const chunks = splitHauntedAnnouncementText(text);
    expect(chunks.length).toBeGreaterThan(1);
    expect(chunks.join(' ')).toBe(text);
    expect(chunks.every(chunk => chunk.length <= 104)).toBe(true);
  });

  it('normalizes whitespace and ignores empty announcements', () => {
    expect(splitHauntedAnnouncementText('  مرحبا   بكم.   ليلة سعيدة!  ')).toEqual(['مرحبا بكم.', 'ليلة سعيدة!']);
    expect(splitHauntedAnnouncementText('   ')).toEqual([]);
  });

  it('splits long text at word boundaries when possible', () => {
    const text = Array.from({ length: 40 }, (_, index) => `كلمة${index}`).join(' ');
    const chunks = splitHauntedAnnouncementText(text);
    expect(chunks.every(chunk => chunk.length <= 104)).toBe(true);
    expect(chunks.join(' ')).toBe(text);
  });
});
