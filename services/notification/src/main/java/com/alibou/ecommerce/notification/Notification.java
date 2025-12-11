package com.alibou.ecommerce.notification;

import com.alibou.ecommerce.kafka.order.OrderConfirmation;
import com.alibou.ecommerce.kafka.payment.PaymentConfirmation;
import jakarta.persistence.*;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;
import org.hibernate.annotations.JdbcTypeCode;
import org.hibernate.type.SqlTypes;

import java.time.LocalDateTime;

@AllArgsConstructor
@NoArgsConstructor
@Builder
@Getter
@Setter
@Entity
public class Notification {

    @Id
    @GeneratedValue(generator = "UUID")
    private String id;

    @Enumerated(EnumType.STRING)
    private NotificationType type;

    private LocalDateTime notificationDate;

    @JdbcTypeCode(SqlTypes.JSON)
    @Column(columnDefinition = "jsonb")
    private OrderConfirmation orderConfirmation;

    @JdbcTypeCode(SqlTypes.JSON)
    @Column(columnDefinition = "jsonb")
    private PaymentConfirmation paymentConfirmation;
}
