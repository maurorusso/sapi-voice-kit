# Spanish words the voices stress wrongly, and how to spell them so they do not.
# The voice receives the respelling; the text on screen is never changed.
#
# Why a respelling and not IPA: for these words the voices ignore the IPA stress
# mark, while a written accent mark is honored.
#
# Used only when the voice speaking is Spanish, and only where pronunciation
# hints are on (not in literal mode). Another language gets its own file here,
# named by its two- or three-letter code.
#
# Rules for entries:
#  - Entry names are single lowercase words; matching is whole-word and case-insensitive,
#    and the respelling takes the capitalization of the word it replaces.
#  - A value is the same word with whatever makes the voice stress it right
#    (usually a written accent), as a single word.
#  - Add an entry only after listening to it with /sapi-voice-kit:test.
#  - Keep this file saved as UTF-8 with BOM.
@{
    # An aguda ending in -l: no written accent (RAE) and stress on the last
    # syllable, but the voices stress the first or second one.
    'natural' = 'naturál'
}
