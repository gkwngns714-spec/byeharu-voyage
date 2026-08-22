// The single import surface for text matching — the `lib/format` idiom applied to the other thing
// the client does with strings. Screens import from 'src/lib/text', never from ./match directly.
export { fold, foldedMatch } from './match'
