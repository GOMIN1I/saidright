import Testing
@testable import SaywellCore

@Suite struct SpokenNumbers {
    @Test func russianDatesTimesAndRooms() {
        #expect(NumberNormalizer.digits("Встреча с Анной Петровой перенесена на пятнадцатое марта в четырнадцать часов тридцать минут. Кабинет двести четыре.")
                == "Встреча с Анной Петровой перенесена на 15 марта в 14 часов 30 минут. Кабинет 204.")
        #expect(NumberNormalizer.digits("двадцать первого апреля") == "21 апреля")
        #expect(NumberNormalizer.digits("третье мая") == "3 мая")
    }

    @Test func russianCompoundsAndCases() {
        #expect(NumberNormalizer.digits("через десять минут") == "через 10 минут")
        #expect(NumberNormalizer.digits("в две тысячи двадцать шестом году") == "в две тысячи двадцать шестом году")
        #expect(NumberNormalizer.digits("две тысячи двадцать шесть") == "2026")
        #expect(NumberNormalizer.digits("около пятисот пользователей") == "около 500 пользователей")
        #expect(NumberNormalizer.digits("Ёлка за триста сорок пять рублей") == "Ёлка за 345 рублей")
    }

    @Test func smallSingleNumbersAndIdiomsStayWords() {
        #expect(NumberNormalizer.digits("один из нас") == "один из нас")
        #expect(NumberNormalizer.digits("я тысячу раз говорил") == "я тысячу раз говорил")
        #expect(NumberNormalizer.digits("встретил семью") == "встретил семью")
        #expect(NumberNormalizer.digits("a hundred times") == "a hundred times")
        #expect(NumberNormalizer.digits("one of them") == "one of them")
    }

    @Test func separateNumbersAreNotMerged() {
        #expect(NumberNormalizer.digits("два три четыре") == "два три четыре")
        #expect(NumberNormalizer.digits("twenty thirty") == "20 30")
    }

    @Test func englishNumbers() {
        #expect(NumberNormalizer.digits("I don't think we need more than three servers for two thousand five hundred users.")
                == "I don't think we need more than three servers for 2500 users.")
        #expect(NumberNormalizer.digits("twenty-five people") == "25 people")
        #expect(NumberNormalizer.digits("one hundred and five") == "105")
        #expect(NumberNormalizer.digits("in nineteen minutes") == "in 19 minutes")
    }

    @Test func textWithoutNumbersIsUnchanged() {
        let t = "Push the commit to GitHub, please — и посмотри, пожалуйста."
        #expect(NumberNormalizer.digits(t) == t)
    }

    @Test func germanCompounds() {
        #expect(NumberNormalizer.digits("Wir brauchen zweitausendfünfhundert Nutzer und drei Server.") == "Wir brauchen 2500 Nutzer und drei Server.")
        #expect(NumberNormalizer.digits("um vierzehn Uhr dreißig") == "um 14 Uhr 30")
        #expect(NumberNormalizer.digits("Raum dreihundertvierundzwanzig") == "Raum 324")
        #expect(NumberNormalizer.digits("einundzwanzig Tage") == "21 Tage")
        #expect(NumberNormalizer.digits("hundert") == "100")
        #expect(NumberNormalizer.digits("Ich schicke dir die Unterlagen morgen früh.") == "Ich schicke dir die Unterlagen morgen früh.")
        #expect(NumberNormalizer.digits("Undine elfenhaft") == "Undine elfenhaft")
    }
}
