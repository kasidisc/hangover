import Foundation

func registerMatcherTests() {
    let never = defaultNeverMove
    let starter = starterRules(screenshotPrefix: nil)
    let downloads = starter.folders[1]
    let desktop = starter.folders[0]

    test("fileExtensionLowercasesLastComponent") {
        expect(fileExtension("foo.tar.gz") == "gz")
        expect(fileExtension("Photo.PNG") == "png")
        expect(fileExtension("Makefile") == "")
    }
    test("skipsPartialDownloads") {
        for n in ["a.zip.download", "b.crdownload", "c.part", "d.opdownload"] {
            expect(isSkipped(n, never), n)
        }
        expect(!isSkipped("a.zip", never))
    }
    test("skipsHiddenAndOfficeLocks") {
        expect(isSkipped(".DS_Store", never))
        expect(isSkipped("~$doc.docx", never))
    }
    test("secretByExtensionAndName") {
        for n in ["id.pem", "mia.env", "teacher-site-smtp_accessKeys.csv", "ses_smtp_password.py"] {
            expect(isSecret(n, never), n)
        }
        expect(!isSecret("report.csv", never))
    }
    test("firstMatchWins") {
        expect(firstMatchingRule("photo.PNG", in: downloads)?.name == "Images")
        expect(firstMatchingRule("x.dmg", in: downloads)?.name == "Installers")
        expect(firstMatchingRule("notes.xyz", in: downloads) == nil)
    }
    test("allFiltersMustMatch") {
        expect(firstMatchingRule("SCR-20261103-ab.png", in: desktop)?.name == "Shottr")
        expect(firstMatchingRule("SCR-notes.txt", in: desktop) == nil)
        expect(firstMatchingRule("MySCR-1.png", in: desktop) == nil)
        expect(firstMatchingRule("Screenshot 2026-11-03 at 10.00.00.png", in: desktop)?.name == "Screenshots")
    }
    test("disabledRuleIgnored") {
        var d = downloads
        d.rules[0].enabled = false
        expect(firstMatchingRule("x.dmg", in: d) == nil)
    }
}
