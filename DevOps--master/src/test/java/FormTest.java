import org.openqa.selenium.By;
import org.openqa.selenium.WebDriver;
import org.openqa.selenium.chrome.ChromeDriver;
import org.openqa.selenium.chrome.ChromeOptions;
import org.openqa.selenium.support.ui.WebDriverWait;
import org.openqa.selenium.support.ui.ExpectedConditions;
import org.testng.Assert;
import org.testng.annotations.Test;

import java.time.Duration;
import java.io.File;

public class FormTest {

    String filePath = new File("index.html").getAbsolutePath();
    String formUrl = "file:///" + filePath;

    public WebDriver buildDriver() {
        ChromeOptions options = new ChromeOptions();
        options.addArguments("--window-size=1366,900");

        if ("true".equals(System.getenv("HEADLESS"))) {
            options.addArguments("--headless=new");
        }

        return new ChromeDriver(options);
    }

    public void fillValidData(WebDriver driver) {
        driver.findElement(By.id("studentName")).clear();
        driver.findElement(By.id("studentName")).sendKeys("Rahul Sharma");

        driver.findElement(By.id("email")).clear();
        driver.findElement(By.id("email")).sendKeys("rahul.sharma@example.com");

        driver.findElement(By.id("mobile")).clear();
        driver.findElement(By.id("mobile")).sendKeys("9876543210");

        driver.findElement(By.id("department")).sendKeys("Computer Science");
        driver.findElement(By.cssSelector("input[name='gender'][value='Male']")).click();

        driver.findElement(By.id("comments")).clear();
        driver.findElement(By.id("comments")).sendKeys(
                "This course content is very clear helpful practical and engaging for all students."
        );
    }

    @Test
    public void testFormPageOpens() {
        WebDriver driver = buildDriver();
        try {
            driver.get(formUrl);

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
            fillValidData(driver);

            driver.findElement(By.id("submitBtn")).click();

            wait.until(ExpectedConditions.textToBePresentInElementLocated(
                    By.id("formMessage"), "Feedback submitted successfully."
            ));

            String status = driver.findElement(By.id("formMessage")).getText();
            Assert.assertEquals(status, "Feedback submitted successfully.");

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
            driver.findElement(By.id("submitBtn")).click();

            wait.until(ExpectedConditions.textToBePresentInElementLocated(
                    By.id("formMessage"), "Please fix the errors"
            ));

            Assert.assertEquals(driver.findElement(By.id("studentNameError")).getText(),
                    "Student name should not be empty.");

            Assert.assertEquals(driver.findElement(By.id("departmentError")).getText(),
                    "Please select your department.");

            Assert.assertEquals(driver.findElement(By.id("genderError")).getText(),
                    "Please select your gender.");

            Assert.assertEquals(driver.findElement(By.id("commentsError")).getText(),
                    "Feedback comments should not be blank.");

        } finally {
            driver.quit();
        }
    }

    @Test
    public void testInvalidEmail() {
        WebDriver driver = buildDriver();

        try {
            driver.get(formUrl);

            driver.findElement(By.id("studentName")).sendKeys("Aman Kumar");
            driver.findElement(By.id("email")).sendKeys("invalid-email");
            driver.findElement(By.id("mobile")).sendKeys("9876543210");
            driver.findElement(By.id("department")).sendKeys("Computer Science");
            driver.findElement(By.cssSelector("input[name='gender'][value='Male']")).click();
            driver.findElement(By.id("comments")).sendKeys(
                    "This form is easy to use and gives clear instructions for every field."
            );

            driver.findElement(By.id("submitBtn")).click();

            Assert.assertEquals(driver.findElement(By.id("emailError")).getText(),
                    "Enter a valid email address.");

        } finally {
            driver.quit();
        }
    }

    @Test
    public void testInvalidMobile() {
        WebDriver driver = buildDriver();

        try {
            driver.get(formUrl);

            driver.findElement(By.id("studentName")).sendKeys("Aman Kumar");
            driver.findElement(By.id("email")).sendKeys("aman@example.com");
            driver.findElement(By.id("mobile")).sendKeys("98AB543");
            driver.findElement(By.id("department")).sendKeys("Computer Science");
            driver.findElement(By.cssSelector("input[name='gender'][value='Male']")).click();
            driver.findElement(By.id("comments")).sendKeys(
                    "The interface is simple responsive and helpful for submitting academic feedback quickly."
            );

            driver.findElement(By.id("submitBtn")).click();

            Assert.assertEquals(driver.findElement(By.id("mobileError")).getText(),
                    "Enter a valid 10-digit mobile number.");

        } finally {
            driver.quit();
        }
    }

    @Test
    public void testDropdownSelection() {
        WebDriver driver = buildDriver();

        try {
            driver.get(formUrl);

            driver.findElement(By.id("department")).sendKeys("Mechanical");

            String selectedValue = driver.findElement(By.id("department")).getAttribute("value");
            Assert.assertEquals(selectedValue, "Mechanical");

        } finally {
            driver.quit();
        }
    }

    @Test
    public void testSubmitAndReset() {
        WebDriver driver = buildDriver();
        WebDriverWait wait = new WebDriverWait(driver, Duration.ofSeconds(8));

        try {
            driver.get(formUrl);
            fillValidData(driver);

            driver.findElement(By.id("resetBtn")).click();

            wait.until(ExpectedConditions.textToBePresentInElementLocated(
                    By.id("formMessage"), "Form reset successfully."
            ));

            Assert.assertEquals(driver.findElement(By.id("studentName")).getAttribute("value"), "");
            Assert.assertEquals(driver.findElement(By.id("email")).getAttribute("value"), "");
            Assert.assertEquals(driver.findElement(By.id("comments")).getAttribute("value"), "");

            fillValidData(driver);

            String departmentValue = driver.findElement(By.id("department")).getAttribute("value");
            String genderChecked = driver.findElement(By.cssSelector("input[name='gender'][value='Male']"))
                    .getAttribute("checked");

            Assert.assertEquals(departmentValue, "Computer Science");
            Assert.assertNotNull(genderChecked);

            driver.findElement(By.id("submitBtn")).click();

            wait.until(ExpectedConditions.textToBePresentInElementLocated(
                    By.id("formMessage"), "Feedback submitted successfully."
            ));

            String status = driver.findElement(By.id("formMessage")).getText();
            Assert.assertEquals(status, "Feedback submitted successfully.");

        } finally {
            driver.quit();
        }
    }
}