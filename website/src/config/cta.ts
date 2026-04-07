export type CtaMode = 'liveFirst' | 'prelaunchFirst';

export interface CtaLink {
  label: string;
  href: string;
  destination: 'app_store' | 'waitlist' | 'referral';
}

export interface CtaConfig {
  mode: CtaMode;
  primary: CtaLink;
  fallback: CtaLink;
}

const DEFAULT_APP_STORE_URL = 'https://apps.apple.com';
const DEFAULT_WAITLIST_URL = '/contact';
const DEFAULT_REFERRAL_URL = '/contact';

function normalizeMode(modeRaw: string | undefined): CtaMode {
  return modeRaw === 'prelaunchFirst' ? 'prelaunchFirst' : 'liveFirst';
}

export function getCtaConfig(env: ImportMetaEnv): CtaConfig {
  const mode = normalizeMode(env.PUBLIC_CTA_MODE);
  const appStoreUrl = env.PUBLIC_APP_STORE_URL || DEFAULT_APP_STORE_URL;
  const waitlistUrl = env.PUBLIC_WAITLIST_URL || DEFAULT_WAITLIST_URL;
  const referralUrl = env.PUBLIC_REFERRAL_URL || DEFAULT_REFERRAL_URL;
  const fallbackPrefersReferral = env.PUBLIC_FALLBACK_DESTINATION === 'referral';

  const fallback: CtaLink = fallbackPrefersReferral
    ? { label: 'Invite a Crafty Friend', href: referralUrl, destination: 'referral' }
    : { label: 'Join the Waitlist', href: waitlistUrl, destination: 'waitlist' };

  const primaryLive: CtaLink = {
    label: 'Download on the App Store',
    href: appStoreUrl,
    destination: 'app_store',
  };

  if (mode === 'prelaunchFirst') {
    return {
      mode,
      primary: { label: 'Join the Waitlist', href: waitlistUrl, destination: 'waitlist' },
      fallback: primaryLive,
    };
  }

  return {
    mode,
    primary: primaryLive,
    fallback,
  };
}
