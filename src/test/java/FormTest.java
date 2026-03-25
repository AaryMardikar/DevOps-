import org.openqa.selenium.By;
import org.openqa.selenium.WebDriver;
import org.openqa.selenium.chrome.ChromeDriver;
import org.openqa.selenium.chrome.ChromeOptions;
import org.openqa.selenium.support.ui.WebDriverWait;
import org.openqa.selenium.support.ui.ExpectedConditions;
import org.testng.Assert;
import org.testng.annotations.Test;

import java.time.Duration;

public class FormTest {

    String formUrl;

    {
        String path = System.getProperty("user.dir") + "/index.html";
        formUrl = "file:///" + path.replace("\\", "/");
        System.out.println("Opening URL: " + formUrl);
    }

    public WebDriver buildDriver() {
        ChromeOptions options = new ChromeOptions();
        options.addArguments("--window-size=1366,900");

        // Important for Jenkins
        options.addArguments("--headless=new");
        options.addArguments("--disable-gpu");
        options.addArguments("--no-sandbox");

        return new ChromeDriver(options);
    }

    public void waitForPage(WebDriver driver) {
        WebDriverWait wait = new WebDriverWait(driver, Duration.ofSeconds(5));
        wait.until(ExpectedConditions.presenceOfElementLocated(By.id("studentName")));
    }

    public void fillValidData(WebDriver driver) {
        driver.findElement(By.id("studentName")).sendKeys("Rahul Sharma");
        driver.findElement(By.id("email")).sendKeys("rahul.sharma@example.com");
        driver.findElement(By.id("mobile")).sendKeys("9876543210");
        driver.findElement(By.id("department")).sendKeys("Computer Science");
        driver.findElement(By.cssSelector("input[name='gender'][value='Male']")).click();
        driver.findElement(By.id("comments")).sendKeys(
                "This course content is very clear helpful practical and engaging for all students."
        );
    }

    @Test
    public void testFormPageOpens() {
        WebDriver driver = buildDriver();
        try {
            driver.get(formUrl);
            waitForPage(driver);

            String title = driver.getTitle();
            String heading = driver.findElement(By.id("form-title")).getText();

            Assert.assertEquals(title, "Student Feedback Registration Form");
            Assert.assertEquals(heading, "Student Feedback Registration Form");

        } finally {
            driver.quit();
        }
    }

    @Test
    public void testValidSubmission() {
        WebDriver driver = buildDriver();
        WebDriverWait wait = new WebDriverWait(driver, Duration.ofSeconds(5));

        try {
            driver.get(formUrl);
            waitForPage(driver);

            fillValidData(driver);
            driver.findElement(By.id("submitBtn")).click();

            wait.until(ExpectedConditions.textToBePresentInElementLocated(
                    By.id("formMessage"), "Feedback submitted successfully."
            ));

            Assert.assertEquals(
                    driver.findElement(By.id("formMessage")).getText(),
                    "Feedback submitted successfully."
            );

        } finally {
            driver.quit();
        }
    }

    @Test
    public void testBlankFieldsValidation() {
        WebDriver driver = buildDriver();
        WebDriverWait wait = new WebDriverWait(driver, Duration.ofSeconds(5));

        try {
            driver.get(formUrl);
            waitForPage(driver);

            driver.findElement(By.id("submitBtn")).click();

            wait.until(ExpectedConditions.textToBePresentInElementLocated(
                    By.id("formMessage"), "Please fix the errors"
            ));

            Assert.assertEquals(driver.findElement(By.id("studentNameError")).getText(),
                    "Student name should not be empty.");

        } finally {
            driver.quit();
        }
    }

    @Test
    public void testInvalidEmail() {
        WebDriver driver = buildDriver();

        try {
            driver.get(formUrl);
            waitForPage(driver);

            driver.findElement(By.id("studentName")).sendKeys("Aman Kumar");
            driver.findElement(By.id("email")).sendKeys("invalid-email");
            driver.findElement(By.id("mobile")).sendKeys("9876543210");

            driver.findElement(By.id("submitBtn")).click();

            Assert.assertEquals(
                    driver.findElement(By.id("emailError")).getText(),
                    "Enter a valid email address."
            );

        } finally {
            driver.quit();
        }
    }

    @Test
    public void testInvalidMobile() {
        WebDriver driver = buildDriver();

        try {
            driver.get(formUrl);
            waitForPage(driver);

            driver.findElement(By.id("studentName")).sendKeys("Aman Kumar");
            driver.findElement(By.id("email")).sendKeys("aman@example.com");
            driver.findElement(By.id("mobile")).sendKeys("98AB543");

            driver.findElement(By.id("submitBtn")).click();

            Assert.assertEquals(
                    driver.findElement(By.id("mobileError")).getText(),
                    "Enter a valid 10-digit mobile number."
            );

        } finally {
            driver.quit();
        }
    }

    @Test
    public void testDropdownSelection() {
        WebDriver driver = buildDriver();

        try {
            driver.get(formUrl);
            waitForPage(driver);

            driver.findElement(By.id("department")).sendKeys("Mechanical");

            String value = driver.findElement(By.id("department")).getAttribute("value");
            Assert.assertEquals(value, "Mechanical");

        } finally {
            driver.quit();
        }
    }

    @Test
    public void testSubmitAndReset() {
        WebDriver driver = buildDriver();
        WebDriverWait wait = new WebDriverWait(driver, Duration.ofSeconds(5));

        try {
            driver.get(formUrl);
            waitForPage(driver);

            fillValidData(driver);
            driver.findElement(By.id("resetBtn")).click();

            wait.until(ExpectedConditions.textToBePresentInElementLocated(
                    By.id("formMessage"), "Form reset successfully."
            ));

            Assert.assertEquals(
                    driver.findElement(By.id("studentName")).getAttribute("value"), ""
            );

        } finally {
            driver.quit();
        }
    }
}