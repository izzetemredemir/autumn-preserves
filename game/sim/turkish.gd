class_name Turkish
extends RefCounted
## L10N-TR · Turkish suffixes for the procedural names (pure string helpers, no state):
## vowel harmony for -lı/-li/-lu/-lü ("Tarçınlı", "Cevizli", "Tuzlu", "Sütlü") and the compound suffix of a noun
## phrase, -ı/-i/-u/-ü after a consonant and -sı/-si/-su/-sü after a vowel ("Elma Reçeli", "Yaban Elması"), with
## consonant softening on words of two or more syllables (p>b, ç>c, t>d, k>ğ, nk>ng: "Şurubu", "Ekmeği").
## Irregular words come from grammar.json tr.compound_exceptions ("Su" -> "Suyu"); a word already in the compound
## form maps to itself ("Sosu" -> "Sosu": "Elma Çatni Sosu", never "Çatni Sosusu").

const VOWELS := "aeıioöuüâîû"
## Last vowel -> the four-way harmony vowel (i-type suffixes).
const HARMONY4 := {"a": "ı", "ı": "ı", "â": "ı", "e": "i", "i": "i", "î": "i", "o": "u", "u": "u", "û": "u", "ö": "ü", "ü": "ü"}
const SOFTEN := {"p": "b", "ç": "c", "t": "d", "k": "ğ"}


## Turkish lower case of one letter: I -> ı and İ -> i (String.to_lower would give i and i̇).
static func lower(c: String) -> String:
	if c == "I":
		return "ı"
	if c == "İ":
		return "i"
	return c.to_lower()


static func is_vowel(c: String) -> bool:
	return VOWELS.contains(lower(c))


## The last vowel of the word ("" when it has none).
static func last_vowel(word: String) -> String:
	for i in range(word.length() - 1, -1, -1):
		var c := lower(word[i])
		if VOWELS.contains(c):
			return c
	return ""


## ı / i / u / ü after the word's last vowel ("i" when it has none).
static func harmony4(word: String) -> String:
	return String(HARMONY4.get(last_vowel(word), "i"))


static func syllables(word: String) -> int:
	var n := 0
	for i in word.length():
		if is_vowel(word[i]):
			n += 1
	return n


## "Tarçın" -> "Tarçınlı", "Ceviz" -> "Cevizli", "Tuz" -> "Tuzlu", "Kestane" -> "Kestaneli".
static func with_li(word: String) -> String:
	return word + "l" + harmony4(word)


## Compound (possessive) form of the last word of a phrase: "Reçel" -> "Reçeli", "Elma" -> "Elması",
## "Şurup" -> "Şurubu", "Salatalık" -> "Salatalığı". `exceptions` maps irregular words to their form.
static func compound(phrase: String, exceptions: Dictionary = {}) -> String:
	var cut := phrase.rfind(" ")
	var head := phrase.substr(0, cut + 1) if cut >= 0 else ""
	var word := phrase.substr(cut + 1) if cut >= 0 else phrase
	if word == "":
		return phrase
	if exceptions.has(word):
		return head + String(exceptions[word])
	var h := harmony4(word)
	var last := lower(word[word.length() - 1])
	if VOWELS.contains(last):
		return head + word + "s" + h
	if syllables(word) >= 2 and SOFTEN.has(last):
		var soft := String(SOFTEN[last])
		if last == "k" and word.length() >= 2 and lower(word[word.length() - 2]) == "n":
			soft = "g"
		word = word.substr(0, word.length() - 1) + soft
	return head + word + h


## The word without a trailing -lı/-li/-lu/-lü ("Ballı" -> "Bal"), for the repeat rule on Turkish words.
static func stem(word: String) -> String:
	var w := word.strip_edges()
	if w.length() > 3:
		var tail := w.right(2)
		if tail in ["lı", "li", "lu", "lü"]:
			return w.left(w.length() - 2)
	return w


## Case-insensitive Turkish equality of two words.
static func same(a: String, b: String) -> bool:
	return lower_word(a) == lower_word(b)


static func lower_word(w: String) -> String:
	var out := ""
	for i in w.length():
		out += lower(w[i])
	return out
