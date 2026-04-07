package com.hamza.ecommerce.kafka;

import com.hamza.ecommerce.customer.CustomerResponse;
import com.hamza.ecommerce.order.PaymentMethod;
import com.hamza.ecommerce.product.PurchaseResponse;

import java.math.BigDecimal;
import java.util.List;

public record OrderConfirmation (
        String orderReference,
        BigDecimal totalAmount,
        PaymentMethod paymentMethod,
        CustomerResponse customer,
        List<PurchaseResponse> products

) {
}
