import { describe, expect, it } from 'vitest';
import { prettyError } from './errors';

describe('localized application errors', () => {
  it('maps known room and social errors to clear Darija messages', () => {
    expect(prettyError({ message: 'ROOM_FULL' })).toBe('الغرفة عامرة.');
    expect(prettyError(new Error('PLAYER_NOT_FOUND'))).toBe('ما لقيناش لاعب بهاد الاسم.');
  });

  it('keeps unknown server messages visible for debugging', () => {
    expect(prettyError({ message: 'UNEXPECTED_DATABASE_ERROR' })).toBe('UNEXPECTED_DATABASE_ERROR');
  });

  it('handles non-Error values without throwing', () => {
    expect(prettyError(null)).toBe('وقع خطأ');
    expect(prettyError('TIME_EXPIRED')).toBe('سالاو 10 ثواني، الجواب ما تقبلش.');
  });
});
