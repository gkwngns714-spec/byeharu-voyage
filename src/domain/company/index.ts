// A COMPANY'S NAME AS IT IS SENT (0503). The rule is the server's alone (`public.company_name_refusal`: 3 to 24 letters and digits with
// one space between words; not a country's, a place's, a trade good's or another company's name) and no screen judges a name. This
// only writes the typed name the way the rule reads it: its ends trimmed, and an accent typed as a separate mark composed with its
// letter (NFC), which the server would otherwise refuse as a special character. Founding and renaming send through here.

/** The longest name the server takes; the field stops there. */
export const COMPANY_NAME_MAX = 24

export function companyNameToSend(typed: string): string {
  return typed.normalize('NFC').trim()
}
